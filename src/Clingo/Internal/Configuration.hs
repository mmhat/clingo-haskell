-- | A module providing direct, but memory managed access to the Clingo
-- configuration interface. The preferred way to interface with configuration is
-- found in 'Clingo.Configuration'. This interface exists solely for users who
-- want to provide their own abstraction, without having to reimplement memory
-- management for the raw versions in 'Clingo.Raw.Configuration'
module Clingo.Internal.Configuration
(
    Configuration,
    ConfigurationType (..),
    CKey,
    configurationRoot,
    configurationType, 
    configurationDescription,
    
    -- ** Array Access
    configurationArraySize,
    configurationArrayAt,

    -- ** Map Access
    configurationMapSize,
    configurationMapSubkeyName,
    configurationMapAt,

    -- ** Value Access
    configurationValueGet,
    configurationValueIsAssigned,
    configurationValueSet
)
where

import Control.Monad.IO.Class
import Control.Monad.Catch
import Numeric.Natural
import Data.Word
import Data.Bits
import Data.Text (Text, pack, unpack)

import Foreign
import Foreign.C

import qualified Clingo.Raw as Raw
import Clingo.Internal.Types
import Clingo.Internal.Utils

newtype CKey = CKey Word32
    deriving (Show, Eq, Ord)

configurationRoot :: (MonadIO m, MonadThrow m) 
                  => Configuration s -> m CKey 
configurationRoot (Configuration c) = 
    CKey . fromIntegral <$> marshal1 (Raw.configurationRoot c)

data ConfigurationType = CType
    { hasValue :: Bool
    , hasArray :: Bool
    , hasMap   :: Bool }
    deriving (Show, Eq, Read, Ord)

fromRawConfigurationType :: Raw.ConfigurationType -> ConfigurationType
fromRawConfigurationType t = CType v a m
    where v = toBool $ t .&. Raw.ConfigValue
          a = toBool $ t .&. Raw.ConfigArray
          m = toBool $ t .&. Raw.ConfigMap

configurationType :: (MonadIO m, MonadThrow m) 
               => Configuration s -> CKey -> m ConfigurationType
configurationType (Configuration s) (CKey k) = 
    fromRawConfigurationType <$> 
        marshal1 (Raw.configurationType s (fromIntegral k))

configurationArraySize :: (MonadIO m, MonadThrow m) 
                    => Configuration s -> CKey -> m Natural
configurationArraySize (Configuration s) (CKey k) = 
    fromIntegral <$> marshal1 (Raw.configurationArraySize s (fromIntegral k))

configurationArrayAt :: (MonadIO m, MonadThrow m)
                  => Configuration s -> CKey -> Natural -> m CKey
configurationArrayAt (Configuration s) (CKey k) offset =
    CKey . fromIntegral <$> marshal1 
        (Raw.configurationArrayAt s (fromIntegral k) (fromIntegral offset))

configurationMapSize :: (MonadIO m, MonadThrow m)
                  => Configuration s -> CKey -> m Natural
configurationMapSize (Configuration s) (CKey k) =
    fromIntegral <$> marshal1 (Raw.configurationMapSize s (fromIntegral k))

configurationMapSubkeyName :: (MonadIO m, MonadThrow m)
                        => Configuration s -> CKey -> Natural -> m Text
configurationMapSubkeyName (Configuration s) (CKey k) offset = do
    cstr <- marshal1 (Raw.configurationMapSubkeyName s (fromIntegral k) 
                                                        (fromIntegral offset))
    pack <$> liftIO (peekCString cstr)

configurationMapAt :: (MonadIO m, MonadThrow m)
                => Configuration s -> CKey -> Text -> m CKey
configurationMapAt (Configuration s) (CKey k) name =
    CKey . fromIntegral <$> marshal1 go
    where go = withCString (unpack name) . 
               flip (Raw.configurationMapAt s (fromIntegral k))

configurationValueGet :: (MonadIO m) 
                      => Configuration s -> CKey -> m Text
configurationValueGet (Configuration s) (CKey k) = liftIO $ do
    len <- marshal1 (Raw.configurationValueGetSize s (fromIntegral k))
    allocaArray (fromIntegral len) $ \arr -> do
        marshal0 (Raw.configurationValueGet s (fromIntegral k) arr len)
        as <- peekArray (fromIntegral len) arr
        pure . pack . map castCCharToChar $ as

configurationDescription :: (MonadIO m, MonadThrow m)
                         => Configuration s -> CKey -> m Text
configurationDescription (Configuration c) (CKey k) = do
    s <- marshal1 (Raw.configurationDescription c (fromIntegral k))
    pack <$> liftIO (peekCString s)

configurationValueIsAssigned :: (MonadIO m, MonadThrow m)
                             => Configuration s -> CKey -> m Bool
configurationValueIsAssigned (Configuration c) (CKey k) =
    toBool <$> marshal1 (Raw.configurationValueIsAssigned c (fromIntegral k))

configurationValueSet :: (MonadIO m, MonadThrow m)
                      => Configuration s -> CKey -> Text -> m ()
configurationValueSet (Configuration s) (CKey k) v = marshal0 go
    where go = withCString (unpack v) $ \str ->
                   Raw.configurationValueSet s (fromIntegral k) str
