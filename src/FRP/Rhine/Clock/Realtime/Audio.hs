{-# LANGUAGE Arrows                #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies          #-}

{-# OPTIONS_GHC -Wno-unticked-promoted-constructors #-}

module FRP.Rhine.Clock.Realtime.Audio
  ( AudioClock (..)
  , AudioRate (..)
  , PureAudioClock (..)
  , pureAudioClockF
  )
  where

-- base
import GHC.Float       (double2Float)
import GHC.TypeLits    (Nat, natVal, KnownNat)
import Data.Time.Clock

-- transformers?
-- TODO Delete as soon as dunai is updated
import Control.Monad.Trans.Class (lift)


-- dunai
import Control.Monad.Trans.MSF.Except

-- rhine
import FRP.Rhine

-- | Rates at which audio signals are typically sampled.
data AudioRate
  = Hz44100
  | Hz48000
  | Hz96000

-- | Converts an 'AudioRate' to its corresponding rate as an 'Integral'.
rateToIntegral :: Integral a => AudioRate -> a
rateToIntegral Hz44100 = 44100
rateToIntegral Hz48000 = 48000
rateToIntegral Hz96000 = 96000


-- TODO Test extensively
{- |
A clock for audio analysis and synthesis.
It internally processes samples in buffers of size 'bufferSize',
(the programmer does not have to worry about this),
at a sample rate of 'rate'
(of type 'AudioRate').
Both these parameters are in the type signature,
so it is not possible to compose signals with different buffer sizes
or sample rates.

After processing a buffer, the clock will wait the remaining time
until the next buffer must be processed,
using system UTC time.
The tag of the clock specifies whether the attempt to finish the last buffer in real time was successful.
A value of 'Nothing' represents success,
a value of @Just double@ represents a lag of 'double' seconds.
-}
data AudioClock (rate :: AudioRate) (bufferSize :: Nat) = AudioClock

class AudioClockRate (rate :: AudioRate) where
  theRate :: AudioClock rate bufferSize -> AudioRate
  theRateIntegral :: Integral a => AudioClock rate bufferSize -> a
  theRateIntegral = rateToIntegral . theRate
  theRateNum :: Num a => AudioClock rate bufferSize -> a
  theRateNum = fromInteger . theRateIntegral

instance AudioClockRate Hz44100 where
  theRate _ = Hz44100

instance AudioClockRate Hz48000 where
  theRate _ = Hz48000

instance AudioClockRate Hz96000 where
  theRate _ = Hz96000


theBufferSize
  :: (KnownNat bufferSize, Integral a)
  => AudioClock rate bufferSize -> a
theBufferSize = fromInteger . natVal


instance (KnownNat bufferSize, AudioClockRate rate) => Clock IO (AudioClock rate bufferSize) where
  type TimeDomainOf (AudioClock rate bufferSize) = UTCTime
  type Tag          (AudioClock rate bufferSize) = Maybe Double

  startClock audioClock = do
    let
      step       = picosecondsToDiffTime -- The only sufficiently precise conversion function
                     $ round (10 ^ (12 :: Integer) / theRateNum audioClock :: Double)
      bufferSize = theBufferSize audioClock
      once f = try $ arrM (lift . f) >>> throwS -- TODO Delete once dunai is updated
      once_ = once . const

      runningClock :: UTCTime -> Maybe Double -> MSF IO () (UTCTime, Maybe Double)
      runningClock initialTime maybeWasLate = safely $ do
        bufferFullTime <- try $ proc () -> do
          n <- count    -< ()
          let nextTime = (realToFrac step * fromIntegral (n :: Int)) `addUTCTime` initialTime
          _ <- throwOn' -< (n >= bufferSize, nextTime)
          returnA       -< (nextTime, if n == 0 then maybeWasLate else Nothing)
        currentTime <- once_ getCurrentTime
        let
          lateDiff = realToFrac $ currentTime `diffUTCTime` bufferFullTime
          late     = if lateDiff > 0 then Just lateDiff else Nothing
        safe $ runningClock bufferFullTime late
    initialTime <- getCurrentTime
    return
      ( runningClock initialTime Nothing
      , initialTime
      )

{- |
A side-effect free clock for audio synthesis and analysis.
The sample rate is given by 'rate' (of type 'AudioRate').
Since this clock does not wait for the completion of buffers,
the producer or the consumer of the signal has the obligation to
synchronise the signal with the system clock, if realtime is desired.
Otherwise, the clock is also suitable e.g. for batch processing of audio files.
-}
data PureAudioClock (rate :: AudioRate) = PureAudioClock

class PureAudioClockRate (rate :: AudioRate) where
  thePureRate :: PureAudioClock rate -> AudioRate
  thePureRateIntegral :: Integral a => PureAudioClock rate -> a
  thePureRateIntegral = rateToIntegral . thePureRate
  thePureRateNum :: Num a => PureAudioClock rate -> a
  thePureRateNum = fromInteger . thePureRateIntegral


instance (Monad m, PureAudioClockRate rate) => Clock m (PureAudioClock rate) where
  type TimeDomainOf (PureAudioClock rate) = Double
  type Tag          (PureAudioClock rate) = ()

  startClock audioClock = return
    ( arr (const (1 / thePureRateNum audioClock)) >>> sumS &&& arr (const ())
    , 0
    )


-- | A rescaled version of 'PureAudioClock' with 'TimeDomain' 'Float'.
type PureAudioClockF (rate :: AudioRate) = RescaledClock (PureAudioClock rate) Float

pureAudioClockF :: PureAudioClockF rate
pureAudioClockF = RescaledClock
  { unscaledClock = PureAudioClock
  , rescale       = double2Float
}