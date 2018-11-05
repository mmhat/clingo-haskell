{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE PatternSynonyms #-}
module Clingo.Control
(
    IOSym,
    Clingo,
    ClingoWarning,
    warningString,
    ClingoSetting (..),
    defaultClingo,
    withDefaultClingo,
    withClingo,
    
    Part (..),

    loadProgram,
    addProgram,
    ground,
    interrupt,
    cleanup,
    registerPropagator,
    registerUnsafePropagator,
    Continue (..),
    SolveResult (..),
    exhausted,
    Solver,
    solve,
    withSolver,
    SolveMode,
    pattern SolveModeAsync,
    pattern SolveModeYield,

    statistics,
    programBuilder,
    configuration,
    backend,
    symbolicAtoms,
    theoryAtoms,

    TruthValue,
    pattern TruthTrue,
    pattern TruthFalse,
    pattern TruthFree,
    negateTruth,
    assignExternal,
    releaseExternal,
    getConst,
    hasConst,
    useEnumAssumption,

    version
)
where

import Control.Monad.IO.Class
import Control.Monad.Trans
import Control.Monad.Catch
import Data.Text (Text, pack, unpack)
import Data.Foldable

import Foreign
import Foreign.C

import Numeric.Natural

import qualified Clingo.Raw as Raw
import Clingo.Internal.Utils
import Clingo.Internal.Symbol
import Clingo.Internal.Types
import Clingo.Solving (solverClose)
import Clingo.Propagation (Propagator, propagatorToIO)

-- | Data type to encapsulate the settings for clingo.
data ClingoSetting = ClingoSetting
    { clingoArgs   :: [String]
    , clingoLogger :: Maybe (ClingoWarning -> Text -> IO ())
    , msgLimit     :: Natural }

-- | Default settings for clingo. This is like calling clingo with no arguments,
-- and no logger.
defaultClingo :: ClingoSetting
defaultClingo = ClingoSetting [] Nothing 0

-- | The entry point into a computation utilizing clingo. Inside, a handle to
-- the clingo solver is available, which can not leave scope. By the same
-- mechanism, derived handles cannot be passed out either.
withClingo :: ClingoSetting -> (forall s. Clingo s r) -> IO r
withClingo settings action = do
    let argc = length (clingoArgs settings)
    argv <- liftIO $ mapM newCString (clingoArgs settings)
    ctrl <- marshall1 $ \x ->
        withArray argv $ \argvArr -> do
            logCB <- maybe (pure nullFunPtr) wrapCBLogger 
                         (clingoLogger settings)
            let argv' = case clingoArgs settings of
                            [] -> nullPtr
                            _  -> argvArr
            Raw.controlNew argv' (fromIntegral argc)
                           logCB nullPtr (fromIntegral . msgLimit $ settings) x
    finally (runClingo ctrl action) $ do
        Raw.controlFree ctrl
        liftIO $ mapM_ free argv

-- | Equal to @withClingo defaultClingo@
withDefaultClingo :: (forall s. Clingo s r) -> IO r
withDefaultClingo = withClingo defaultClingo

-- | Load a logic program from a file.
loadProgram :: FilePath -> Clingo s ()
loadProgram path = askC >>= \ctrl ->
    marshall0 (withCString path (Raw.controlLoad ctrl))

-- | Add an ungrounded logic program to the solver as a 'Text'. This function
-- can be used in order to utilize clingo's parser. See 'parseProgram' for when
-- you want to modify the AST before adding it.
addProgram :: Foldable t
           => Text                      -- ^ Part Name
           -> t Text                    -- ^ Part Arguments
           -> Text                      -- ^ Program Code
           -> Clingo s ()
addProgram name params code = askC >>= \ctrl -> marshall0 $ 
    withCString (unpack name) $ \n ->
        withCString (unpack code) $ \c -> do
            ptrs <- mapM (newCString . unpack) (toList params)
            withArrayLen ptrs $ \s ps ->
                Raw.controlAdd ctrl n ps (fromIntegral s) c

-- | A 'Part' is one building block of a logic program in clingo. Parts can be
-- grounded separately and can have arguments, which need to be initialized with
-- the solver.
data Part s = Part
    { partName   :: Text
    , partParams :: [Symbol s] }

rawPart :: Part s -> IO Raw.Part
rawPart p = Raw.Part <$> newCString (unpack (partName p))
                     <*> newArray (map rawSymbol . partParams $ p)
                     <*> pure (fromIntegral (length . partParams $ p))

freeRawPart :: Raw.Part -> IO ()
freeRawPart p = do
    free (Raw.partName p)
    free (Raw.partParams p)

-- | Ground logic program parts. A callback can be provided to inject symbols
-- when needed.
ground :: [Part s]      -- ^ Parts to be grounded
       -> Maybe 
          (Location -> Text -> [Symbol s] -> ([Symbol s] -> IO ()) -> IO ())
                        -- ^ Callback for injecting symbols
       -> Clingo s ()
ground parts extFun = askC >>= \ctrl -> marshall0 $ do
    rparts <- mapM rawPart parts
    res <- withArrayLen rparts $ \len arr -> do
        groundCB <- maybe (pure nullFunPtr) wrapCBGround extFun
        Raw.controlGround ctrl arr (fromIntegral len) groundCB nullPtr
    mapM_ freeRawPart rparts
    return res

wrapCBGround :: MonadIO m
             => (Location -> Text -> [Symbol s] 
                          -> ([Symbol s] -> IO ()) -> IO ())
             -> m (FunPtr (Raw.CallbackGround ()))
wrapCBGround f = liftIO $ Raw.mkCallbackGround go
    where go :: Raw.CallbackGround ()
          go loc name arg args _ cbSym _ = reraiseIO $ do
              loc'  <- fromRawLocation =<< peek loc
              name' <- pack <$> peekCString name
              syms  <- mapM pureSymbol =<< peekArray (fromIntegral args) arg
              f loc' name' syms (unwrapCBSymbol $ Raw.getCallbackSymbol cbSym)

unwrapCBSymbol :: Raw.CallbackSymbol () -> ([Symbol s] -> IO ())
unwrapCBSymbol f syms =
    withArrayLen (map rawSymbol syms) $ \len arr -> 
        marshall0 (f arr (fromIntegral len) nullPtr)

-- | Interrupt the current solve call.
interrupt :: Clingo s ()
interrupt = Raw.controlInterrupt =<< askC

-- | Clean up the domains of clingo's grounding component using the solving
-- component's top level assignment.
--
-- This function removes atoms from domains that are false and marks atoms as
-- facts that are true.  With multi-shot solving, this can result in smaller
-- groundings because less rules have to be instantiated and more
-- simplifications can be applied.
cleanup :: Clingo s ()
cleanup = marshall0 . Raw.controlCleanup =<< askC

-- | A datatype that can be used to indicate whether solving shall continue or
-- not.
data Continue = Continue | Stop
    deriving (Eq, Show, Ord, Read, Enum, Bounded)

continueBool :: Continue -> Bool
continueBool Continue = True
continueBool Stop = False

-- | Solve the currently grounded logic program enumerating its models. Takes an
-- optional event callback. Since Clingo 5.2, the callback is no longer the only
-- way to interact with models. The callback can still be used to obtain the
-- same functionality as before. It will be called with 'Nothing' when there is
-- no more model.
--
-- Furthermore, asynchronous solving and iterative solving is also controlled
-- from this function. See "Clingo.Solving" for more details.
--
-- The 'Solver' must be closed explicitly after use. See 'withSolver' for a
-- bracketed version.
solve :: SolveMode -> [AspifLiteral s]
      -> Maybe (Maybe (Model s) -> IOSym s Continue)
      -> Clingo s (Solver s)
solve mode assumptions onEvent = do
    ctrl <- askC
    Solver <$> marshall1 (go ctrl)
    where go ctrl x =
              withArrayLen (map rawAspifLiteral assumptions) $ \len arr -> do
                  eventCB <- maybe (pure nullFunPtr) wrapCBEvent onEvent
                  Raw.controlSolve 
                    ctrl (rawSolveMode mode) 
                    arr (fromIntegral len) eventCB nullPtr 
                    x

withSolver :: [AspifLiteral s] 
    -> (forall s1. Solver s1 -> IOSym s1 r) 
    -> Clingo s r
withSolver assumptions f = do
    x <- solve SolveModeYield assumptions Nothing
    Clingo (lift (f x)) 
        `finally` solverClose x

wrapCBEvent :: MonadIO m
            => (Maybe (Model s) -> IOSym s Continue) 
            -> m (FunPtr (Raw.CallbackEvent ()))
wrapCBEvent f = liftIO $ Raw.mkCallbackEvent go
    where go :: Raw.SolveEvent 
             -> Ptr Raw.Model 
             -> Ptr a 
             -> Ptr Raw.CBool 
             -> IO Raw.CBool
          go ev m _ r = reraiseIO $ do
              m' <- case ev of
                        Raw.SolveEventModel  -> Just . Model <$> peek m
                        Raw.SolveEventFinish -> pure Nothing
                        _ -> error "wrapCBEvent: Invalid solve event"
              poke r . fromBool. continueBool =<< iosym (f m')

-- | Obtain statistics handle. See 'Clingo.Statistics'.
statistics :: Clingo s (Statistics s)
statistics = fmap Statistics . marshall1 . Raw.controlStatistics =<< askC

-- | Obtain program builder handle. See 'Clingo.ProgramBuilding'.
programBuilder :: Clingo s (ProgramBuilder s)
programBuilder = fmap ProgramBuilder . marshall1 
               . Raw.controlProgramBuilder =<< askC

-- | Obtain backend handle. See 'Clingo.ProgramBuilding'.
backend :: Clingo s (Backend s)
backend = fmap Backend . marshall1 . Raw.controlBackend =<< askC

-- | Obtain configuration handle. See 'Clingo.Configuration'.
configuration :: Clingo s (Configuration s)
configuration = fmap Configuration . marshall1 
              . Raw.controlConfiguration =<< askC

-- | Obtain symbolic atoms handle. See 'Clingo.Inspection.SymbolicAtoms'.
symbolicAtoms :: Clingo s (SymbolicAtoms s)
symbolicAtoms = fmap SymbolicAtoms . marshall1 
              . Raw.controlSymbolicAtoms =<< askC

-- | Obtain theory atoms handle. See 'Clingo.Inspection.TheoryAtoms'.
theoryAtoms :: Clingo s (TheoryAtoms s)
theoryAtoms = fmap TheoryAtoms . marshall1 . Raw.controlTheoryAtoms =<< askC

-- | Configure how learnt constraints are handled during enumeration.
-- 
-- If the enumeration assumption is enabled, then all information learnt from
-- the solver's various enumeration modes is removed after a solve call. This
-- includes enumeration of cautious or brave consequences, enumeration of
-- answer sets with or without projection, or finding optimal models, as well
-- as clauses added with clingo_solve_control_add_clause().
useEnumAssumption :: Bool -> Clingo s ()
useEnumAssumption b = askC >>= \ctrl -> 
    marshall0 $ Raw.controlUseEnumAssumption ctrl (fromBool b)

-- | Assign a truth value to an external atom.
-- 
-- If the atom does not exist or is not external, this is a noop.
assignExternal :: AspifLiteral s -> TruthValue -> Clingo s ()
assignExternal s t = askC >>= \ctrl -> 
    marshall0 $ Raw.controlAssignExternal ctrl (rawAspifLiteral s) (rawTruthValue t)

-- | Release an external atom.
-- 
-- After this call, an external atom is no longer external and subject to
-- program simplifications.  If the atom does not exist or is not external,
-- this is a noop.
releaseExternal :: AspifLiteral s -> Clingo s ()
releaseExternal s = askC >>= \ctrl -> 
    marshall0 $ Raw.controlReleaseExternal ctrl (rawAspifLiteral s)

-- | Get the symbol for a constant definition @#const name = symbol@.
getConst :: Text -> Clingo s (Symbol s)
getConst name = askC >>= \ctrl -> pureSymbol =<< marshall1 (go ctrl)
    where go ctrl x = withCString (unpack name) $ \cstr -> 
                          Raw.controlGetConst ctrl cstr x

-- | Check if there is a constant definition for the given constant.
hasConst :: Text -> Clingo s Bool
hasConst name = askC >>= \ctrl -> toBool <$> marshall1 (go ctrl)
    where go ctrl x = withCString (unpack name) $ \cstr ->
                          Raw.controlHasConst ctrl cstr x


-- | Register a custom propagator with the solver.
--
-- If the sequential flag is set to true, the propagator is called
-- sequentially when solving with multiple threads.
-- 
-- See the 'Clingo.Propagation' module for more information.
registerPropagator :: Bool -> Propagator s -> Clingo s ()
registerPropagator sequ prop = do
    ctrl <- askC
    prop' <- rawPropagator . propagatorToIO $ prop
    res <- liftIO $ with prop' $ \ptr ->
               Raw.controlRegisterPropagator ctrl ptr nullPtr (fromBool sequ)
    checkAndThrow res

-- | Like 'registerPropagator' but allows using 'IOPropagator's from
-- 'Clingo.Internal.Propagation'. This function is unsafe!
registerUnsafePropagator :: Bool -> IOPropagator s -> Clingo s ()
registerUnsafePropagator sequ prop = do
    ctrl <- askC
    prop' <- rawPropagator prop
    res <- liftIO $ with prop' $ \ptr ->
               Raw.controlRegisterPropagator ctrl ptr nullPtr (fromBool sequ)
    checkAndThrow res

-- | Get clingo version.
version :: MonadIO m => m (Int, Int, Int)
version = do 
    (a,b,c) <- marshall3V Raw.version
    return (fromIntegral a, fromIntegral b, fromIntegral c)
