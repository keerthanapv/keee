{-# OPTIONS_HADDOCK hide #-}

{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Imj.Game.Hamazed.Level
    ( LevelSpec(..)
    , LevelEssence(..)
    , mkLevelEssence
    , mkEmptyLevelEssence
    , Level(..)
    , mkLevel
    , LevelTarget(..)
    , TargetConstraint(..)
    , initialLaserAmmo
    , firstLevel
    , lastLevel
    ) where


import           Imj.Prelude
import           Imj.Game.Level

initialLaserAmmo :: Int
initialLaserAmmo = 10

data Level = Level {
    _levelSpec :: {-# UNPACK #-} !LevelEssence
  , getLevelOutcome' :: {-unpack sum-} !(Maybe LevelOutcome)
} deriving (Generic, Show)

mkLevel :: LevelEssence -> Level
mkLevel = flip Level Nothing

data LevelEssence = LevelEssence {
    getLevelNumber' :: {-# UNPACK #-} !LevelNumber
    -- ^ From 1 to 12
  , _levelTarget :: {-unpack sum-} !LevelTarget
  , _levelFlyingNumbers :: ![Int]
} deriving (Generic, Show)
instance Binary LevelEssence
instance NFData LevelEssence

data LevelTarget = LevelTarget {-# UNPACK #-} !Int {-unpack sum-} !TargetConstraint
  deriving (Generic, Show)
instance Binary LevelTarget
instance NFData LevelTarget

data TargetConstraint =
    CanOvershoot
  | CannotOvershoot
  deriving (Generic, Show)
instance Binary TargetConstraint
instance NFData TargetConstraint

data LevelSpec = LevelSpec {
    levelNumber :: {-# UNPACK #-} !LevelNumber
  , _targetConstraint :: {-unpack sum-} !TargetConstraint
} deriving(Generic, Show)
instance Binary LevelSpec
instance NFData LevelSpec

mkEmptyLevelEssence :: LevelEssence
-- we don't use 0 a target else the level would be won immediately.
mkEmptyLevelEssence = LevelEssence 0 (LevelTarget 1 CannotOvershoot) []

mkLevelEssence :: LevelSpec -> LevelEssence
mkLevelEssence (LevelSpec n co) =
  let numbers = [1..(3 + fromIntegral n)] -- more and more numbers as level increases
      target = sum numbers `quot` 2
  in LevelEssence n (LevelTarget target co) numbers

-- | 12
lastLevel :: LevelNumber
lastLevel = 12

-- | 1
firstLevel :: LevelNumber
firstLevel = 1
