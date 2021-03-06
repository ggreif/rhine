{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes       #-}
{-# LANGUAGE TypeFamilies     #-}

import FRP.Rhine
import FRP.Rhine.Clock.Realtime.Millisecond
import FRP.Rhine.Schedule.Concurrently
import FRP.Rhine.ResamplingBuffer.Collect

-- | Create a simple message containing the time stamp since program start,
--   for each tick of the clock.
--   Since 'createMessage' works for arbitrary clocks (and doesn't need further input data),
--   it is a 'Behaviour'.
--   @td@ is the 'TimeDomain' of any clock used to sample,
--   and it needs to be constrained in order for time differences
--   to have a 'Show' instance.
createMessage
  :: (Monad m, Show (Diff td))
  => String
  -> Behaviour m td String
createMessage str
  =   timeInfoOf sinceStart >-> arr show
  >-> arr (("Clock " ++ str ++ " has ticked at: ") ++)

-- | Output a message /every second/ (= every 1000 milliseconds).
--   Let us assume we want to assure that 'printEverySecond'
--   is only called every second,
--   then we constrain its type signature with the clock @Millisecond 1000@.
printEverySecond :: Show a => SyncSF IO (Millisecond 1000) a ()
printEverySecond = arrMSync print

-- | Specialise 'createMessage' to a specific clock.
ms500 :: SyncSF IO (Millisecond 500) () String
ms500 = createMessage "500 MS"


ms1200 :: SyncSF IO (Millisecond 1200) () String
ms1200 = createMessage "1200 MS"

-- | Create messages every 500 ms and every 1200 ms,
--   collecting all of them in a list,
--   which is output every second.
main :: IO ()
main = flow $
  ms500 @@ waitClock **@ concurrently @** ms1200 @@ waitClock
  >-- collect -@- concurrently -->
  printEverySecond @@ waitClock

-- | Uncomment the following for a type error (the clocks don't match):

-- typeError = ms500 >>> printEverySecond
