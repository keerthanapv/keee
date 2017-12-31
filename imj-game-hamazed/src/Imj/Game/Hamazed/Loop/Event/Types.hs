{-# OPTIONS_HADDOCK hide #-}

{-# LANGUAGE NoImplicitPrelude #-}

module Imj.Game.Hamazed.Loop.Event.Types
        ( Event(..)
        , Deadline(..)
        , ActionTarget(..)
        , DeadlineType(..)
        , MetaAction(..)
        -- * Reexports (for haddock hyperlinks)
        , module Imj.Game.Hamazed.World.Types
        , module Imj.Graphics.Animation.Design.Create
        ) where

import           Imj.Prelude

import           Imj.Game.Hamazed.Types
import           Imj.Game.Hamazed.World.Types
import           Imj.Geo.Discrete
import           Imj.Graphics.Animation.Design.Create
import           Imj.Timing

-- | A foreseen game or animation update.
data Deadline = Deadline {
    _deadlineTime :: !KeyTime
  , _deadlineType :: !DeadlineType
} deriving(Eq, Show)

data Event = Action !ActionTarget !Direction
           -- ^ A player action on an 'ActionTarget' in a 'Direction'.
           | Timeout !Deadline
           -- ^ The 'Deadline' that needs to be handled immediately.
           | StartLevel !Int
           -- ^ New level.
           | EndGame
           -- ^ End of game.
           | Interrupt !MetaAction
           -- ^ A game interruption.
           deriving(Eq, Show)

data MetaAction = Quit
                -- ^ The player decided to quit the game.
                | Configure
                -- ^ The player wants to configure the game /(Not implemented yet)/
                | Help
                -- ^ The player wants to read the help page /(Not implemented yet)/
                deriving(Eq, Show)

data DeadlineType = MoveFlyingItems
                  -- ^ Move 'Number's and 'BattleShip' according to their current
                  -- speeds.
                  | Animate
                  -- ^ Update one or more 'Animation's.
                  | DisplayContinueMessage
                  -- ^ Show the /Hit a key to continue/ message
                  | AnimateUI
                  -- ^ Update the inter-level animation
                  deriving(Eq, Show)

data ActionTarget = Ship
                  -- ^ The player wants to accelerate the 'BattleShip'
                  | Laser
                  -- ^ The player wants to shoot with the laser.
                  deriving(Eq, Show)