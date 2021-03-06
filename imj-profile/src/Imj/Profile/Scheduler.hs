{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DeriveGeneric #-}

module Imj.Profile.Scheduler
  ( withTestScheduler'
  , decodeProgressFile
  , mkResultFromStats
  , continue
  , TestProgress
  , mkZeroProgress
  , showStep
  )
  where

import           Imj.Prelude hiding(div)

import           Prelude(putStrLn, putStr, print)
import           Control.Concurrent(threadDelay)
import           Control.Concurrent.MVar.Strict (MVar, readMVar)
import           Data.List.NonEmpty (NonEmpty(..))
import           Data.List as List
import           Data.Map.Strict(Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import           Numeric(showFFloat)
import           System.Random.MWC
import           System.IO(stdout, hFlush)

import           Imj.Data.AlmostFloat
import           Imj.Profile.Types
import           Imj.Space.Types

import           Imj.Graphics.Color
import qualified Imj.Graphics.Text.ColorString as CS
import           Imj.Graphics.Text.Render
import           Imj.Profile.Intent
import           Imj.Profile.Reports
import           Imj.Profile.Result
import           Imj.Profile.Results
import           Imj.Random.MWC.Util
import           Imj.Timing

-- | For each world:
-- Using a single seed group, find /a/ strategy that works within a given time upper bound.
-- Using all seed groups, and the found strategy as a hint, find the best strategy.
-- Record the best strategies, and use them as hints in subsequent iterations.
withTestScheduler' :: MVar UserIntent
                   -> (Maybe (Time Duration System) -> Properties -> NonEmpty GenIO -> IO (Maybe (MkSpaceResult SmallWorld, Statistics)))
                   -- ^ Function to test
                   -> TestProgress
                   -> (TestProgress -> UserIntent -> IO ())
                   -- ^ function to write reports
                   -> IO ()
withTestScheduler' intent testF initialProgress report =
  flip (!!) 0 <$> seedGroups >>= start >>= \finalProgress ->
    readMVar intent >>= report finalProgress
 where
  start firstSeedGroup = do
    mapM_ CS.putStrLn $ showStep initialProgress
    go initialProgress
   where
    go :: TestProgress -> IO TestProgress
    go p@(TestProgress _ !dt hints strategiesSpecs remaining tooHard results) = do
      {-
      putStrLn "remaining"
      mapM_ print remaining
      putStrLn "tooHard"
      mapM_ print tooHard
      -}
      onReport (report p) intent
      continue intent >>= bool
        (return p)
        (case remaining of
          [] ->
            if null tooHard
              then
                return p
              else do
                -- reverse to keep the sorting property of 'willTestInIteration' (see doc).
                let newProgress = updateProgress (nextDt dt) hints (reverse tooHard) [] results p
                mapM_ CS.putStrLn $ showStep newProgress
                go newProgress
          []:rest -> go $ p{willTestInIteration = rest}
          smalls@(smallEasy:smallHards):biggerOrDifferents -> do
            case shouldTest smallEasy results of
              ClosestSmallerSizeHasNoResult -> do
                putStrLn $ "[skip - smaller size has no result] " ++ prettyShowSWCharacteristics smallEasy
                trySmallsLater
              ClosestSmallerSizeHas res -> do
                case summarize res of
                  NoResult -> do
                    putStrLn $ "[skip - smaller size has no result] " ++ prettyShowSWCharacteristics smallEasy
                    trySmallsLater
                  NTimeouts _ -> do
                    putStrLn $ "[skip - smaller size has timeouts] " ++ prettyShowSWCharacteristics smallEasy
                    trySmallsLater
                  FinishedAverage duration _ ->
                    -- The 0.1 multiplicative factor was introduced to discard difficult tests.
                    if duration > 0.1 .* dt
                      then do
                        putStrLn $ "[skip - smaller size has long duration] " ++ prettyShowSWCharacteristics smallEasy
                        trySmallsLater
                      else
                        run
              FirstSize ->
                run
           where
            trySmallsLater =
              go $ updateProgress dt hints biggerOrDifferents (smalls:tooHard) results p

            run = do
                putStrLn $ "[test] " ++ prettyShowSWCharacteristics smallEasy
                let hintsSpecsByDistance = sortOn snd $ Map.assocs tmp
                    hintsSet = Map.keysSet tmp
                    tmp =
                      Map.fromListWith min $
                        map (\(w,spec) -> (spec, smallWorldCharacteristicsDistance smallEasy w)) $
                        Map.assocs hints
                    orderedStrategies =
                      map fst hintsSpecsByDistance ++
                      Set.toList (Set.difference strategiesSpecs hintsSet)
                    -- this might not work at the beginning of the algo, but once we have sufficient
                    -- results it is ok.
                    nCloseHints = foldl' (\n (_,dist) -> if dist <= 2 then n+1 else n) 0 hintsSpecsByDistance
                    nMaxUsedStrategies = max 8 nCloseHints
                    (used,unused) = splitAt nMaxUsedStrategies orderedStrategies
                mapM_ putStrLn $ showArrayN (Just ["Hint", "Distance"]) $ map (\(h,d) -> [show h, showFFloat (Just 2) d ""]) hintsSpecsByDistance
                go' smallEasy used >>= maybe
                  trySmallsLater
                  (\(strategy,_res) -> do
                      (refined, resultsBySeeds) <- refineWithHint smallEasy testF strategy used
                      let newResults = addUnrefinedResult smallEasy refined unused resultsBySeeds results
                          newHints = Map.insert smallEasy refined hints
                      mapM_ CS.putStrLn $ showResults newResults
                      putStrLn $ prettyShowSWCharacteristics smallEasy
                      CS.putStrLn $ showRefined strategy refined
                      go $ updateProgress dt newHints (smallHards:biggerOrDifferents) tooHard newResults p)

            go' _ [] = return Nothing
            go' world@(SWCharacteristics sz _ _) (strategy:otherStrategies) = do
              putStrLn $ "[try 1 group] " ++ show strategy
              fmap (uncurry mkResultFromStats) <$> withNumberedSeeds (testF (Just dt) (mkProperties world $ fmap (toVariants sz) strategy)) firstSeedGroup
                 >>= maybe
                  (go' world otherStrategies)
                  (\case
                    Timeout -> error "logic"
                    NotStarted -> error "logic"
                    f@(Finished dt' _) -> bool
                      (onTimeoutMismatch dt dt' >> go' world otherStrategies)
                      (return $ Just (strategy,f))
                      $ dt' <= dt))

  nextDt = (.*) multDt
  multDt = 6

onTimeoutMismatch :: Time Duration System -> Time Duration System -> IO ()
onTimeoutMismatch specified actual
  | actual <= specified = error "logic"
  | actual <= 2 .* specified = return ()
  | otherwise = putStrLn $ unwords ["Big timeout mismatch:", showTime specified, showTime actual]

continue :: MVar UserIntent -> IO Bool
continue intent = readMVar intent >>= \case
  Cancel -> return False
  Pause _ -> do
    CS.putStrLn $ CS.colored "Test is paused, press 'Space' to continue..." yellow
    let waitForNewIntent = do
          threadDelay 100000
          readMVar intent >>= \case
            Pause _ -> waitForNewIntent
            _ -> return ()
    waitForNewIntent
    continue intent
  _ -> return True

-- note that even in case of timeout we could provide some stats.
mkResultFromStats :: MkSpaceResult a -> Statistics -> TestStatus Statistics
mkResultFromStats res stats = case res of
  NeedMoreTime -> Timeout
  Impossible err -> error $ "impossible :" ++ show err
  Success _ -> Finished (totalDuration $ durations stats) stats


-- | Given a hint variant, computes the best variant, taking the time of the hint
-- as a reference to early-discard others.
refineWithHint :: SmallWorldCharacteristics Program
               -> (Maybe (Time Duration System) -> Properties -> NonEmpty GenIO -> IO (Maybe (MkSpaceResult a, Statistics)))
               -> Maybe MatrixVariantsSpec
               -- ^ This is the hint : a variant which we think is one of the fastest.
               -> [Maybe MatrixVariantsSpec]
               -- ^ The candidates (the hint can be in this list, but it will be filtered away)
               -> IO (Maybe MatrixVariantsSpec, Map (NonEmpty SeedNumber) (TestStatus Statistics))
               -- ^ The best
refineWithHint world@(SWCharacteristics sz _ _) testF hintStrategy strategies = do
  putStrLn "[refine] "
  res <- mkHintStats >>= mkBestSofar hintStrategy >>= go (filter (/= hintStrategy) strategies)
  putStrLn ""
  return res
 where
  go [] (BestSofar s l _) = return (s, l)
  go (candidate:candidates) bsf@(BestSofar _ _ (DurationConstraints maxTotal maxIndividual)) =
    mkStatsWithConstraint >>= either
      (const $ return bsf)
      (mkBestSofar candidate) >>= go candidates
   where
    mkStatsWithConstraint :: IO (Either () (Map (NonEmpty SeedNumber) (TestStatus Statistics)))
    mkStatsWithConstraint  = do
      putStr "." >> hFlush stdout
      seedGroups >>= ho [] zeroDuration
     where
      ho l totalSofar remaining
        | totalSofar >= maxTotal = return $ Left ()
        | otherwise = case remaining of
            [] ->
              return $ Right $ Map.fromList l
            seedGroup:groups -> do
              let maxDt = min maxIndividual $ maxTotal |-| totalSofar
                  props = mkProperties world $ fmap (toVariants sz) candidate
              fmap (uncurry mkResultFromStats) <$> withNumberedSeeds (testF (Just maxDt) props) seedGroup >>= maybe
                (return $ Left ())
                (\case
                  Timeout -> error "logic"
                  NotStarted -> error "logic"
                  f@(Finished dt _) ->
                    bool
                      (onTimeoutMismatch maxDt dt >> return (Left ()))
                      (ho ((seedGroup,f):l) (totalSofar |+| dt) groups)
                      $ dt <= maxDt)
  mkHintStats :: IO (Map (NonEmpty SeedNumber) (TestStatus Statistics))
  mkHintStats =
    seedGroups >>= fmap Map.fromList . mapM
      (\seedGroup -> (,) seedGroup . uncurry mkResultFromStats . fromMaybe (error "logic") <$> -- Nothing is an error because we don't specify a timeout
        withNumberedSeeds (testF Nothing $ mkProperties world $ fmap (toVariants sz) hintStrategy) seedGroup)

data BestSofar = BestSofar {
    _strategy :: !(Maybe MatrixVariantsSpec)
  , _results :: Map (NonEmpty SeedNumber) (TestStatus Statistics)
  , _inducedContraints :: !DurationConstraints
}
instance Show BestSofar where
  show (BestSofar a _ b) = show (b,a)

mkBestSofar :: Maybe MatrixVariantsSpec -> Map (NonEmpty SeedNumber) (TestStatus Statistics) -> IO BestSofar
mkBestSofar s l = do
  let res = BestSofar s l $ mkDurationConstraints $ Map.elems l
  print res
  return res
 where
  mkDurationConstraints :: [TestStatus Statistics]
                        -> DurationConstraints
  mkDurationConstraints results =
    DurationConstraints sumTime $ 3 .* maxTime
   where
    sumTime = foldl' (\t r -> getTime r |+| t) zeroDuration results
    maxTime = foldl' (\t r -> max (getTime r) t) zeroDuration results

    getTime = \case
      Timeout -> error "logic"
      NotStarted -> error "logic"
      Finished dt _ -> dt

data DurationConstraints = DurationConstraints {
    _maxTotal :: !(Time Duration System)
  , _maxIndividual :: !(Time Duration System)
} deriving(Show)


smallWorldCharacteristicsDistance :: SmallWorldCharacteristics a -> SmallWorldCharacteristics b -> Float
smallWorldCharacteristicsDistance (SWCharacteristics sz cc p) (SWCharacteristics sz' cc' p') =
  -- These changes have the same impact on distance:
  --   doubled area
  --   proba 0.6 -> 0.7
  --   2 cc -> 3 cc
  --   4 cc -> 5 cc
  doubleSize + 10 * almostDistance p p' + fromIntegral (dCC (min cc cc') (max cc cc'))
 where
   -- c1 <= c2
   dCC c1 c2
    | c1 == c2 = 0
    | c1 == 1 = (c2 - c1) * 10
    | otherwise = c2 - c1

   doubleSize -- 1 when size doubles
    | a == a' = 0
    | a' == 0 = 1000000
    | ratio > 1 = ratio - 1
    | otherwise = (1 / ratio) - 1
    where
      a = area sz
      a' = area sz'
      ratio = fromIntegral a / fromIntegral a'
