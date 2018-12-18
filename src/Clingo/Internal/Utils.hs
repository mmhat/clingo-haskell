{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE PatternSynonyms #-}
module Clingo.Internal.Utils
(
    ClingoException (..),
    pattern Raw.ErrorRuntime,
    getException,
    ClingoWarning (..),
    warningString,

    checkAndThrow,
    marshall0,
    marshall1,
    marshall1V,
    marshall1A,
    marshall1RT,
    marshall2,
    marshall3V,
    reraiseIO
)
where

import Control.Monad
import Control.Monad.IO.Class
import Control.Monad.Catch
import Data.Typeable
import Data.Text (Text, pack)

import Foreign
import Foreign.C

import qualified Clingo.Raw as Raw

data ClingoException = ClingoException Raw.ClingoError String
    deriving (Show, Typeable)

instance Exception ClingoException

newtype ClingoWarning = ClingoWarning Raw.ClingoWarning
    deriving (Show, Typeable)

instance Exception ClingoWarning
    
getException :: MonadIO m => m ClingoException
getException = liftIO $ do
    code <- Raw.errorCode
    estr <- peekCString =<< Raw.errorString code
    return $ ClingoException code estr
{-# INLINE getException #-}

warningString :: MonadIO m => ClingoWarning -> m Text
warningString (ClingoWarning w) = liftIO $
    Raw.warningString w >>= fmap pack . peekCString

checkAndThrow :: (MonadIO m, MonadThrow m) => Raw.CBool -> m ()
checkAndThrow b = unless (toBool b) $ getException >>= throwM
{-# INLINE checkAndThrow #-}

checkAndThrowRT :: (MonadIO m, MonadThrow m) 
                => m a -> Raw.CBool -> m (Maybe a)
checkAndThrowRT a b
    | toBool b = Just <$> a
    | otherwise = do
        exc <- getException
        case exc of
            ClingoException Raw.ErrorRuntime _ -> return Nothing
            _ -> throwM exc
{-# INLINE checkAndThrowRT #-}

marshall0 :: (MonadIO m, MonadThrow m) => IO Raw.CBool -> m ()
marshall0 action = liftIO action >>= checkAndThrow
{-# INLINE marshall0 #-}

marshall1 :: (Storable a, MonadIO m, MonadThrow m) 
          => (Ptr a -> IO Raw.CBool) -> m a
marshall1 action = do
    (res, a) <- liftIO $ alloca $ \ptr -> do
        res <- action ptr
        a <- peek ptr
        return (res, a)
    checkAndThrow res
    return a
{-# INLINE marshall1 #-}

marshall1V :: (Storable a, MonadIO m) 
           => (Ptr a -> IO ()) -> m a
marshall1V action =
    liftIO $ alloca $ \ptr -> do
        _ <- action ptr
        peek ptr
{-# INLINE marshall1V #-}

marshall1RT :: (Storable a, MonadIO m)
            => (Ptr a -> IO Raw.CBool) -> m (Maybe a)
marshall1RT action =
    liftIO $ alloca $ \ptr -> do
        res <- action ptr
        checkAndThrowRT (peek ptr) res
{-# INLINE marshall1RT #-}

marshall2 :: (Storable a, Storable b, MonadIO m, MonadThrow m)
          => (Ptr a -> Ptr b -> IO Raw.CBool) -> m (a,b)
marshall2 action = do
    (res, (a,b)) <- liftIO $ alloca $ \ptr1 -> 
        alloca $ \ptr2 -> do
            res <- action ptr1 ptr2
            a <- peek ptr1
            b <- peek ptr2
            return (res, (a,b))
    checkAndThrow res
    return (a,b)
{-# INLINE marshall2 #-}

marshall1A :: (Storable a, MonadIO m, MonadThrow m)
           => (Ptr (Ptr a) -> Ptr CSize -> IO Raw.CBool) -> m [a]
marshall1A action = do
    (res, as) <- liftIO $ alloca $ \ptr1 -> 
        alloca $ \ptr2 -> do
            res  <- action ptr1 ptr2
            len  <- peek ptr2
            arrp <- peek ptr1
            arr  <- peekArray (fromIntegral len) arrp
            return (res, arr)
    checkAndThrow res
    return as
{-# INLINE marshall1A #-}

marshall3V :: (Storable a, Storable b, Storable c, MonadIO m)
           => (Ptr a -> Ptr b -> Ptr c -> IO ()) -> m (a,b,c)
marshall3V action = do
    (a,b,c) <- liftIO $ alloca $ \ptr1 -> 
        alloca $ \ptr2 -> 
            alloca $ \ptr3 -> do
                _ <- action ptr1 ptr2 ptr3
                a <- peek ptr1
                b <- peek ptr2
                c <- peek ptr3
                return (a,b,c)
    return (a,b,c)
{-# INLINE marshall3V #-}

reraiseIO :: IO a -> IO Raw.CBool
reraiseIO action = catch (action >> return (fromBool True)) $ 
    \(ClingoException e s) -> do
        withCString s $ Raw.setError e
        return (fromBool False)
{-# INLINE reraiseIO #-}
