{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

module Imj.Music.Record
      ( recordMusic
      , mkSequencerFromRecording
      , playOnce
      , playOnceFrom
      , insertRecording
      ) where

import           Imj.Prelude
import           Control.Concurrent(threadDelay)
import qualified Data.Map.Strict as Map
import qualified Data.Vector as V

import           Imj.Music.Types
import           Imj.Timing

-- | Adds an 'AbsolutelyTimedMusicalEvent' to a 'Recording'
recordMusic :: AbsolutelyTimedMusicalEvent i -> Recording i -> Recording i
recordMusic e (Recording r) = Recording (flip (:) r e)

mkSequencerFromRecording :: (NFData i, Ord i)
                         => k
                         -> Recording i
                         -> Time Point System
                         -- ^ Defining the zero-time of the sequence.
                         -> IO (Either Text (Sequencer k i))
mkSequencerFromRecording _ (Recording []) _ = return $ Left "empty recording"
mkSequencerFromRecording k (Recording r) start = do
  mus <- mkMusicLoop v
  return $ Right $ Sequencer start (firstTime...start) $ Map.singleton k mus
 where
  rr = reverse r
  (ATM _ firstTime) = fromMaybe (error "logic") $ listToMaybe rr
  v = V.fromList $ map (\(ATM m t) -> RTM m $ firstTime...t) rr

{-# INLINABLE insertRecording #-}
insertRecording :: (Ord k, Ord i, NFData i)
                => Recording i -> k -> Sequencer k i -> IO (Either Text (Sequencer k i, MusicLoop i))
insertRecording (Recording []) _ _ = return $ Left "Recording is empty"
insertRecording (Recording r@(_:_)) k (Sequencer curPeriodStart periodLength ls)
  | periodLength == zeroDuration = return $ Left "sequencer with zero duration"
  | otherwise = do
      mus <- mkMusicLoop v
      return $ Right $
        (Sequencer curPeriodStart periodLength $ Map.insert k mus ls
       , mus)
 where
  rr = reverse r
  (ATM _ firstTime) = fromMaybe (error "logic") $ listToMaybe rr
  recordingTimeShift = (fromIntegral nPeriodsShift) .* periodLength
  nPeriodsShift = floor $ (curPeriodStart...firstTime) ./ periodLength :: Int
  refTime = addDuration recordingTimeShift curPeriodStart
  v = V.fromList $ map (\(ATM m t) -> RTM m $ refTime...t) rr

-- TODO pass the MIDI offset (in nanoseconds) to apply to notes.
-- TODO when notes have midi timestamps, instead of waiting all the way,
-- wait just a litle (up to half a second before the note) and send the event
-- with its midi timestamp.
playOnceFrom :: MonadIO m
             => (MusicalEvent i -> m ())
             -- ^ Will be called for each generated 'MusicalEvent'
             -> Time Point System
             -- ^ The music reference time
             -> Time Duration System
             -- ^ The elapsed time since the reference time.
             -> V.Vector (RelativelyTimedMusicalEvent i)
             -> m ()
playOnceFrom play begin elapsed l =
  playOnce play v begin
 where
  v = V.dropWhile (\(RTM _ dt) -> dt < elapsed) l

playOnce :: MonadIO m
         => (MusicalEvent i -> m ())
         -> V.Vector (RelativelyTimedMusicalEvent i)
         -> Time Point System
         -- ^ The reference time
         -> m ()
playOnce play v begin =

  go 0

 where

  !len = V.length v

  go index
    | index == len = return ()
    | otherwise = do
      let (RTM m dt) = V.unsafeIndex v index
          nextEventTime = addDuration dt begin
      now <- liftIO getSystemTime
      let waitDuration = now...nextEventTime
      liftIO $ threadDelay $ fromIntegral $ toMicros waitDuration
      play m
      go $ index + 1
