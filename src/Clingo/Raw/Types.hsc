{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Clingo.Raw.Types
(
    CBool,

    -- * Basic types
    Literal,
    Atom,
    Identifier,
    Weight,
    Logger,
    mkCallbackLogger,
    Location (..),

    -- * Symbols
    Signature,
    Symbol,

    -- * Model and Solving
    Model (..),
    SolveHandle(..),
    SolveControl (..),

    -- * Symbolic and Theory Atoms
    SymbolicAtoms (..),
    SymbolicAtomIterator,
    TheoryAtoms (..),

    -- * Propagators
    PropagateInit (..),
    Assignment (..),
    PropagateControl (..),
    CallbackPropagatorInit,
    mkCallbackPropagatorInit,
    CallbackPropagatorPropagate,
    mkCallbackPropagatorPropagate,
    CallbackPropagatorUndo,
    mkCallbackPropagatorUndo,
    CallbackPropagatorCheck,
    mkCallbackPropagatorCheck,
    Propagator (..),

    -- * Program Builder
    WeightedLiteral (..),
    Backend (..),
    ProgramBuilder (..),

    -- * Configuration & Statistics
    Configuration (..),
    Statistics (..),

    -- * Program Inspection
    GroundProgramObserver (..),
    mkGpoInitProgram,
    mkGpoBeginStep,
    mkGpoEndStep,
    mkGpoRule,
    mkGpoWeightRule,
    mkGpoMinimize,
    mkGpoProject,
    mkGpoExternal,
    mkGpoAssume,
    mkGpoHeuristic,
    mkGpoAcycEdge,
    mkGpoTheoryTermNum,
    mkGpoTheoryTermStr,
    mkGpoTheoryTermCmp,
    mkGpoTheoryElement,
    mkGpoTheoryAtom,
    mkGpoTheoryAtomGrd,

    -- * Control
    Control (..),
    Part (..),
    CallbackSymbol,
    mkCallbackSymbol,
    getCallbackSymbol,
    CallbackGround,
    mkCallbackGround,
    CallbackEvent,
    mkCallbackEvent,
    CallbackFinish,
    mkCallbackFinish
)
where

import Data.Int
import Data.Word
import Foreign
import Foreign.C

import Clingo.Raw.Enums

#include <clingo.h>

type Literal = #type clingo_literal_t
type Atom = #type clingo_atom_t
type Identifier = #type clingo_id_t
type Weight = #type clingo_weight_t

type Logger a = ClingoWarning -> Ptr CChar -> Ptr a -> IO ()

foreign import ccall "wrapper" mkCallbackLogger ::
    Logger a -> IO (FunPtr (Logger a))

data Location = Location
    { locBeginFile :: CString
    , locEndFile   :: CString
    , locBeginLine :: #type size_t
    , locEndLine   :: #type size_t
    , locBeginCol  :: #type size_t
    , locEndCol    :: #type size_t }
    deriving (Eq, Show)

instance Storable Location where
    sizeOf _ = #{size clingo_location_t}
    alignment = sizeOf

    peek p = Location 
        <$> (#{peek clingo_location_t, begin_file} p)
        <*> (#{peek clingo_location_t, end_file} p)
        <*> (#{peek clingo_location_t, begin_line} p)
        <*> (#{peek clingo_location_t, end_line} p)
        <*> (#{peek clingo_location_t, begin_column} p)
        <*> (#{peek clingo_location_t, end_column} p)

    poke p l = do
        (#poke clingo_location_t, begin_file) p (locBeginFile l)
        (#poke clingo_location_t, end_file) p (locEndFile l)
        (#poke clingo_location_t, begin_line) p (locBeginLine l)
        (#poke clingo_location_t, end_line) p (locEndLine l)
        (#poke clingo_location_t, begin_column) p (locBeginCol l)
        (#poke clingo_location_t, end_column) p (locEndCol l)

type Signature = #type clingo_signature_t
type Symbol = #type clingo_symbol_t

-- data SymbolicLiteral = SymbolicLiteral
--     { slitSymbol   :: Symbol
--     , slitPositive :: CBool }
-- 
-- instance Storable SymbolicLiteral where
--     sizeOf _ = #{size clingo_symbolic_literal_t}
--     alignment = sizeOf
--     peek p = SymbolicLiteral
--          <$> (#{peek clingo_symbolic_literal_t, symbol} p)
--          <*> (#{peek clingo_symbolic_literal_t, positive} p)
-- 
--     poke p lit = do
--         (#poke clingo_symbolic_literal_t, symbol) p (slitSymbol lit)
--         (#poke clingo_symbolic_literal_t, positive) p (slitPositive lit)

newtype SolveHandle = SolveHandle (Ptr SolveHandle) deriving Storable
newtype SolveControl = SolveControl (Ptr SolveControl) deriving Storable
newtype Model = Model (Ptr Model) deriving Storable
newtype SymbolicAtoms = SymbolicAtoms (Ptr SymbolicAtoms) deriving Storable

type SymbolicAtomIterator = #type clingo_symbolic_atom_iterator_t

newtype TheoryAtoms = TheoryAtoms (Ptr TheoryAtoms) deriving Storable
newtype PropagateInit = PropagateInit (Ptr PropagateInit) deriving Storable
newtype Assignment = Assignment (Ptr Assignment) deriving Storable
newtype PropagateControl = PropagateControl (Ptr PropagateControl) 
    deriving Storable

type CallbackPropagatorInit a = 
    PropagateInit -> Ptr a -> IO (CBool)

foreign import ccall "wrapper" mkCallbackPropagatorInit ::
    CallbackPropagatorInit a -> IO (FunPtr (CallbackPropagatorInit a))

type CallbackPropagatorPropagate a = 
    PropagateControl -> Ptr Literal -> CSize -> Ptr a -> IO CBool

foreign import ccall "wrapper" mkCallbackPropagatorPropagate ::
    CallbackPropagatorPropagate a -> IO (FunPtr (CallbackPropagatorPropagate a))

type CallbackPropagatorUndo a = 
    PropagateControl -> Ptr Literal -> CSize -> Ptr a -> IO CBool

foreign import ccall "wrapper" mkCallbackPropagatorUndo ::
    CallbackPropagatorUndo a -> IO (FunPtr (CallbackPropagatorUndo a))

type CallbackPropagatorCheck a = 
    PropagateControl -> Ptr a -> IO CBool

foreign import ccall "wrapper" mkCallbackPropagatorCheck ::
    CallbackPropagatorCheck a -> IO (FunPtr (CallbackPropagatorCheck a))

data Propagator a = Propagator
    { propagatorInit      :: FunPtr (CallbackPropagatorInit a)
    , propagatorPropagate :: FunPtr (CallbackPropagatorPropagate a)
    , propagatorUndo      :: FunPtr (CallbackPropagatorUndo a)
    , propagatorCheck     :: FunPtr (CallbackPropagatorCheck a)
    }

instance Storable (Propagator a) where
    sizeOf _ = #{size clingo_propagator_t}
    alignment = sizeOf
    peek p = Propagator 
         <$> (#{peek clingo_propagator_t, init} p)
         <*> (#{peek clingo_propagator_t, propagate} p)
         <*> (#{peek clingo_propagator_t, undo} p)
         <*> (#{peek clingo_propagator_t, check} p)

    poke p prop = do
        (#poke clingo_propagator_t, init) p (propagatorInit prop)
        (#poke clingo_propagator_t, propagate) p (propagatorPropagate prop)
        (#poke clingo_propagator_t, undo) p (propagatorUndo prop)
        (#poke clingo_propagator_t, check) p (propagatorCheck prop)

data WeightedLiteral = WeightedLiteral
    { wlLiteral :: Literal
    , wlWeight  :: Weight
    }

instance Storable WeightedLiteral where
    sizeOf _ = #{size clingo_weighted_literal_t}
    alignment = sizeOf
    peek p = WeightedLiteral
         <$> (#{peek clingo_weighted_literal_t, literal} p)
         <*> (#{peek clingo_weighted_literal_t, weight} p)

    poke p wl = do
        (#poke clingo_weighted_literal_t, literal) p (wlLiteral wl)
        (#poke clingo_weighted_literal_t, weight) p (wlWeight wl)

newtype Backend = Backend (Ptr Backend) deriving Storable
newtype Configuration = Configuration (Ptr Configuration) deriving Storable
newtype Statistics = Statistics (Ptr Statistics) deriving Storable
newtype ProgramBuilder = ProgramBuilder (Ptr ProgramBuilder) deriving Storable

data GroundProgramObserver a = GroundProgramObserver
    { gpoInitProgram   :: FunPtr (CBool -> Ptr a -> IO CBool)
    , gpoBeginStep     :: FunPtr (Ptr a -> IO CBool)
    , gpoEndStep       :: FunPtr (Ptr a -> IO CBool)
    , gpoRule          :: FunPtr (CBool -> Ptr Atom -> CSize 
                                               -> Ptr Literal -> CSize 
                                               -> Ptr a -> IO CBool)
    , gpoWeightRule    :: FunPtr (CBool -> Ptr Atom -> CSize -> Weight 
                                               -> Ptr WeightedLiteral -> CSize 
                                               -> Ptr a -> IO CBool)
    , gpoMinimize      :: FunPtr (Weight -> Ptr WeightedLiteral -> CSize 
                                         -> Ptr a -> IO CBool)
    , gpoProject       :: FunPtr (Ptr Atom -> CSize -> Ptr a -> IO CBool)
    , gpoExternal      :: FunPtr (Atom -> ExternalType -> Ptr a -> IO CBool)
    , gpoAssume        :: FunPtr (Ptr Literal -> CSize -> Ptr a -> IO CBool)
    , gpoHeuristic     :: FunPtr (Atom -> HeuristicType -> CInt 
                                       -> CUInt -> Ptr Literal -> CSize 
                                       -> Ptr a -> IO CBool)
    , gpoAcycEdge      :: FunPtr (CInt -> CInt -> Ptr Literal -> CSize 
                                       -> Ptr a -> IO CBool)
    , gpoTheoryTermNum :: FunPtr (Identifier -> CInt -> Ptr a -> IO CBool)
    , gpoTheoryTermStr :: FunPtr (Identifier -> Ptr CChar -> Ptr a -> IO CBool)
    , gpoTheoryTermCmp :: FunPtr (Identifier -> CInt -> Ptr Identifier -> CSize 
                                             -> Ptr a -> IO CBool)
    , gpoTheoryElement :: FunPtr (Identifier -> Ptr Identifier -> CSize 
                                             -> Ptr Literal -> CSize -> Ptr a 
                                             -> IO CBool)
    , gpoTheoryAtom    :: FunPtr (Identifier -> Identifier -> Ptr Identifier 
                                             -> CSize -> IO CBool)
    , gpoTheoryAtomGrd :: FunPtr (Identifier -> Identifier -> Ptr Identifier 
                                             -> CSize -> Identifier 
                                             -> Identifier -> Ptr a 
                                             -> IO CBool)
    }

foreign import ccall "wrapper" mkGpoInitProgram :: 
    (CBool -> Ptr a -> IO CBool) -> IO (FunPtr (CBool -> Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoBeginStep :: 
    (Ptr a -> IO CBool) -> IO (FunPtr (Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoEndStep ::
    (Ptr a -> IO CBool) -> IO (FunPtr (Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoRule ::
    (CBool -> Ptr Atom -> CSize -> Ptr Literal -> CSize -> Ptr a -> IO CBool) -> IO (FunPtr (CBool -> Ptr Atom -> CSize -> Ptr Literal -> CSize -> Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoWeightRule ::
    (CBool -> Ptr Atom -> CSize -> Weight -> Ptr WeightedLiteral -> CSize -> Ptr a -> IO CBool) -> IO (FunPtr (CBool -> Ptr Atom -> CSize -> Weight -> Ptr WeightedLiteral -> CSize -> Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoMinimize ::
    (Weight -> Ptr WeightedLiteral -> CSize -> Ptr a -> IO CBool) -> IO (FunPtr (Weight -> Ptr WeightedLiteral -> CSize -> Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoProject ::
    (Ptr Atom -> CSize -> Ptr a -> IO CBool) -> IO (FunPtr (Ptr Atom -> CSize -> Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoExternal ::
    (Atom -> ExternalType -> Ptr a -> IO CBool) -> IO (FunPtr (Atom -> ExternalType -> Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoAssume ::
    (Ptr Literal -> CSize -> Ptr a -> IO CBool) -> IO (FunPtr (Ptr Literal -> CSize -> Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoHeuristic ::
    (Atom -> HeuristicType -> CInt -> CUInt -> Ptr Literal -> CSize -> Ptr a -> IO CBool) -> IO (FunPtr (Atom -> HeuristicType -> CInt -> CUInt -> Ptr Literal -> CSize -> Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoAcycEdge ::
    (CInt -> CInt -> Ptr Literal -> CSize -> Ptr a -> IO CBool) -> IO (FunPtr (CInt -> CInt -> Ptr Literal -> CSize -> Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoTheoryTermNum ::
    (Identifier -> CInt -> Ptr a -> IO CBool) -> IO (FunPtr (Identifier -> CInt -> Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoTheoryTermStr ::
    (Identifier -> Ptr CChar -> Ptr a -> IO CBool) -> IO (FunPtr (Identifier -> Ptr CChar -> Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoTheoryTermCmp ::
    (Identifier -> CInt -> Ptr Identifier -> CSize -> Ptr a -> IO CBool) -> IO (FunPtr (Identifier -> CInt -> Ptr Identifier -> CSize -> Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoTheoryElement ::
    (Identifier -> Ptr Identifier -> CSize -> Ptr Literal -> CSize -> Ptr a -> IO CBool) -> IO (FunPtr (Identifier -> Ptr Identifier -> CSize -> Ptr Literal -> CSize -> Ptr a -> IO CBool))
foreign import ccall "wrapper" mkGpoTheoryAtom ::
    (Identifier -> Identifier -> Ptr Identifier -> CSize -> IO CBool) -> IO (FunPtr (Identifier -> Identifier -> Ptr Identifier -> CSize -> IO CBool))
foreign import ccall "wrapper" mkGpoTheoryAtomGrd ::
    (Identifier -> Identifier -> Ptr Identifier -> CSize -> Identifier -> Identifier -> Ptr a -> IO CBool) -> IO (FunPtr (Identifier -> Identifier -> Ptr Identifier -> CSize -> Identifier -> Identifier -> Ptr a -> IO CBool))

instance Storable (GroundProgramObserver a) where
    sizeOf _ = #{size clingo_ground_program_observer_t}
    alignment = sizeOf
    peek p = GroundProgramObserver
        <$> (#{peek clingo_ground_program_observer_t, init_program} p)
        <*> (#{peek clingo_ground_program_observer_t, begin_step} p)
        <*> (#{peek clingo_ground_program_observer_t, end_step} p)
        <*> (#{peek clingo_ground_program_observer_t, rule} p)
        <*> (#{peek clingo_ground_program_observer_t, weight_rule} p)
        <*> (#{peek clingo_ground_program_observer_t, minimize} p)
        <*> (#{peek clingo_ground_program_observer_t, project} p)
        <*> (#{peek clingo_ground_program_observer_t, external} p)
        <*> (#{peek clingo_ground_program_observer_t, assume} p)
        <*> (#{peek clingo_ground_program_observer_t, heuristic} p)
        <*> (#{peek clingo_ground_program_observer_t, acyc_edge} p)
        <*> (#{peek clingo_ground_program_observer_t, theory_term_number} p)
        <*> (#{peek clingo_ground_program_observer_t, theory_term_string} p)
        <*> (#{peek clingo_ground_program_observer_t, theory_term_compound} p)
        <*> (#{peek clingo_ground_program_observer_t, theory_element} p)
        <*> (#{peek clingo_ground_program_observer_t, theory_atom} p)
        <*> (#{peek clingo_ground_program_observer_t, theory_atom_with_guard} p)

    poke p g = do
        (#poke clingo_ground_program_observer_t, init_program) p 
            (gpoInitProgram g)
        (#poke clingo_ground_program_observer_t, begin_step) p (gpoBeginStep g)
        (#poke clingo_ground_program_observer_t, end_step) p (gpoEndStep g)
        (#poke clingo_ground_program_observer_t, rule) p (gpoRule g)
        (#poke clingo_ground_program_observer_t, weight_rule) p 
            (gpoWeightRule g)
        (#poke clingo_ground_program_observer_t, minimize) p (gpoMinimize g)
        (#poke clingo_ground_program_observer_t, project) p (gpoProject g)
        (#poke clingo_ground_program_observer_t, external) p (gpoExternal g)
        (#poke clingo_ground_program_observer_t, assume) p (gpoAssume g)
        (#poke clingo_ground_program_observer_t, heuristic) p (gpoHeuristic g)
        (#poke clingo_ground_program_observer_t, acyc_edge) p (gpoAcycEdge g)
        (#poke clingo_ground_program_observer_t, theory_term_number) p 
            (gpoTheoryTermNum g)
        (#poke clingo_ground_program_observer_t, theory_term_string) p 
            (gpoTheoryTermStr g)
        (#poke clingo_ground_program_observer_t, theory_term_compound) p 
            (gpoTheoryTermCmp g)
        (#poke clingo_ground_program_observer_t, theory_element) p 
            (gpoTheoryElement g)
        (#poke clingo_ground_program_observer_t, theory_atom) p 
            (gpoTheoryAtom g)
        (#poke clingo_ground_program_observer_t, theory_atom_with_guard) p 
            (gpoTheoryAtomGrd g)

newtype Control = Control (Ptr Control) deriving Storable

data Part = Part
    { partName   :: CString
    , partParams :: Ptr Symbol
    , partSize   :: CSize
    }

instance Storable Part where
    sizeOf _ = #{size clingo_part_t}
    alignment = sizeOf
    peek p = Part
         <$> (#{peek clingo_part_t, name} p)
         <*> (#{peek clingo_part_t, params} p)
         <*> (#{peek clingo_part_t, size} p)

    poke p part = do
         (#poke clingo_part_t, name) p (partName part)
         (#poke clingo_part_t, params) p (partParams part)
         (#poke clingo_part_t, size) p (partSize part)

type CallbackSymbol a = Ptr Symbol -> CSize -> Ptr a -> IO CBool
type CallbackGround a = 
    Ptr Location -> Ptr CChar -> Ptr Symbol -> CSize -> Ptr a 
                 -> FunPtr (CallbackSymbol a) -> Ptr a -> IO CBool
type CallbackEvent a = SolveEvent -> Ptr Model -> Ptr a -> Ptr CBool -> IO CBool
type CallbackFinish a = SolveResult -> Ptr a -> IO CBool

foreign import ccall "wrapper" mkCallbackGround ::
    CallbackGround a -> IO (FunPtr (CallbackGround a))

foreign import ccall "wrapper" mkCallbackSymbol ::
    CallbackSymbol a -> IO (FunPtr (CallbackSymbol a))

foreign import ccall "dynamic" getCallbackSymbol ::
    FunPtr (CallbackSymbol a) -> CallbackSymbol a

foreign import ccall "wrapper" mkCallbackFinish ::
    CallbackFinish a -> IO (FunPtr (CallbackFinish a))

foreign import ccall "wrapper" mkCallbackEvent ::
    CallbackEvent a -> IO (FunPtr (CallbackEvent a))
