{-# OPTIONS_HADDOCK hide #-}
-- | Contains types that the game server doesn't need to know about.

{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE UndecidableInstances #-}

module Imj.Game.Hamazed.Types
    ( GracefulProgramEnd(..)
    , UnexpectedProgramEnd(..)
    , HamazedClientSideServer
    , Game(..)
    , GameTime
    , GameState(..)
    , AnimatedLine(..)
    , UpdateEvent
    , EventGroup(..)
    , GenEvent(..)
    , initialViewMode
    -- * Reexports
    , module Imj.Game.Hamazed.Chat
    , module Imj.Game.Hamazed.Level.Types
    , module Imj.Game.Hamazed.World.Types
    , UIAnimation
    , RecordDraw
    ) where

import           Imj.Prelude
import           Control.Exception.Base(Exception(..))
import           Data.Map.Strict(Map)
import           Data.Text(unpack)

import           Imj.Client.Class
import           Imj.ClientServer.Types
import           Imj.Graphics.RecordDraw
import           Imj.Game.Hamazed.Level.Types
import           Imj.Game.Hamazed.Loop.Event.Types
import           Imj.Game.Hamazed.Network.Types
import           Imj.Game.Hamazed.World.Types

import           Imj.Game.Hamazed.Chat
import           Imj.Game.Hamazed.Loop.Timing
import           Imj.Graphics.UI.Animation
import           Imj.Graphics.Text.ColorString

-- Note that we don't have GracefulClientEnd, because we use exitSuccess in that case
-- and don't need an exception.
data GracefulProgramEnd =
    GracefulServerEnd
instance Exception GracefulProgramEnd
instance Show GracefulProgramEnd where
  show GracefulServerEnd        = withNewline "Graceful server shutdown."

data UnexpectedProgramEnd =
    UnexpectedProgramEnd !Text
  | ErrorFromServer !String
instance Exception UnexpectedProgramEnd
instance Show UnexpectedProgramEnd where
  show (UnexpectedProgramEnd s) = withNewline $ unpack s
  show (ErrorFromServer s)      = withNewline $ "An error occured in the Server: " ++ s

withNewline :: String -> String
withNewline = flip (++) "\n"


data EventGroup s c = EventGroup {
    events :: ![UpdateEvent s c]
  , _eventGroupHasPrincipal :: !Bool
  , _eventGroupUpdateDuration :: !(Time Duration System)
  , _eventGroupVisibleTimeRange :: !(Maybe (TimeRange System))
  -- ^ TimeRange of /visible/ events deadlines
}

-- | Regroups events that can be handled immediately by the client.
type UpdateEvent s c = Either (ServerEvent s) c

{- Regroups all kinds of events. -}
data GenEvent e =
    Evt {-unpack sum-} !(CliEvtT e)
    -- ^ Are generated by the client and can be handled by the client immediately.
  | CliEvt {-unpack sum-} !(ClientEventT (ClientServerT e))
    -- ^ Are generated by the client but can't be handled by the client, and are sent to the game server.
  | SrvEvt {-unpack sum-} !(ServerEvent (ClientServerT e))
    -- ^ Are generated by the game server or by the client, and can be handled by the client immediately.
    deriving(Generic)
instance (Show (CliEvtT e), ClientServer (ClientServerT e)) => Show (GenEvent e) where
  show (Evt e) = show("Evt",e)
  show (CliEvt e) = show("CliEvt",e)
  show (SrvEvt e) = show("SrvEvt",e)

type HamazedClientSideServer = Server ColorScheme WorldParameters

data Game = Game {
    getClientState :: {-# UNPACK #-} !ClientState
  , getGameState' :: !GameState
  , _gameSuggestedPlayerName :: {-unpack sum-} !SuggestedPlayerName
  , getServer' :: {-unpack sum-} !HamazedClientSideServer
  -- ^ The server that runs the game
  , connection' :: {-unpack sum-} !ConnectionStatus
  , getChat' :: !Chat
}

{-| 'GameState' has two fields of type 'World' : during 'Level' transitions,
we draw the /old/ 'World' while using the /new/ 'World' 's
dimensions to animate the UI accordingly. -}
data GameState = GameState {
    currentWorld :: !World
  , mayFutureWorld :: !(Maybe World)
    -- ^ Maybe the world that we transition to (when a level is over).
    -- Once the transition is over, we replace 'currentWorld' with this 'Just' value.
  , _gameStateShotNumbers :: ![ShotNumber]
    -- ^ Which 'Number's were shot
  , getGameLevel :: !Level
    -- ^ The current 'Level'
  , getUIAnimation :: !UIAnimation
    -- ^ Inter-level animation.
  , getDrawnClientState :: [( ColorString -- The raw message, just used to compare with new messages. For rendering,
                                          -- AnimatedLine is used.
                          , AnimatedLine)]
  , getScreen :: {-# UNPACK #-} !Screen
  , getViewMode' :: {-unpack sum-} !ViewMode
  , getPlayers' :: !(Map ShipId Player)
}

data AnimatedLine = AnimatedLine {
    getRecordDrawEvolution :: !(Evolution RecordDraw)
  , getALFrame :: !Frame
  , getALDeadline :: Maybe Deadline
} deriving(Generic, Show)

initialViewMode :: ViewMode
initialViewMode = CenterSpace
