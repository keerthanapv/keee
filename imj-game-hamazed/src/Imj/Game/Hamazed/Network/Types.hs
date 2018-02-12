{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module Imj.Game.Hamazed.Network.Types
      ( GameNode(..)
      , ConnectionStatus(..)
      , NoConnectReason(..)
      , SuggestedPlayerName(..)
      , PlayerName(..)
      , ClientId(..)
      , ClientType(..)
      , ClientState(..)
      , StateNature(..)
      , StateValue(..)
      , ClientEvent(..)
      , ServerEvent(..)
      , ClientQueues(..)
      , Server(..)
      , ServerPort(..)
      , ServerName(..)
      , getServerNameAndPort
      , PlayerNotif(..)
      , GameNotif(..)
      , GameStep(..)
      , toTxt
      , toTxt'
      , welcome
      ) where

import           Imj.Prelude hiding(intercalate)
import           Control.Concurrent.STM(TQueue)
import           Control.DeepSeq(NFData)
import qualified Data.Binary as Bin(encode, decode)
import           Data.String(IsString)
import           Data.Text(intercalate)
import           Data.Text.Lazy(unpack)
import           Data.Text.Lazy.Encoding(decodeUtf8)
import           Network.WebSockets(WebSocketsData(..), DataMessage(..))

import           Imj.Game.Hamazed.Chat
import           Imj.Game.Hamazed.Level.Types
import           Imj.Game.Hamazed.Loop.Event.Types
import           Imj.Game.Hamazed.World.Space.Types

data Server = Distant ServerName ServerPort
            | Local ServerPort
  deriving(Generic, Show)

data ClientType =
    WorldCreator
  | JustPlayer
  deriving(Generic, Show, Eq)

instance Binary ClientType

data ClientState = ClientState !StateNature !StateValue
  deriving(Generic, Show)

data StateNature = Ongoing | Done
  deriving(Generic, Show)
instance Binary StateNature

data StateValue =
    Excluded
    -- ^ The player is not part of the game
  | Setup
  -- ^ The player is configuring the game
  | PlayLevel
  -- ^ The player is playing the game
  deriving(Generic, Show, Eq)
instance Binary StateValue
instance NFData StateValue

data ClientId = ClientId {
    getPlayerName :: !PlayerName -- ^ primary key
  , getClientId :: !ShipId -- ^ primary key
} deriving(Generic, Show)
instance NFData ClientId

-- | Match only on 'ShipId'.
instance Eq ClientId where
  x == y = (getClientId x) == (getClientId y)
  {-# INLINABLE (==) #-}

instance Binary ClientId

data GameNode =
    GameServer !Server
  | GameClient !ClientQueues !Server
  -- ^ A client can be connected to one server only.

-- TODO should I use -funbox-strict-fields to force deep evaluation of thunks when inserting in the queues?
data ClientQueues = ClientQueues {
    getInputQueue :: !(TQueue ServerEvent)
  , getOutputQueue :: !(TQueue ClientEvent)
}

-- | An event generated by the client, sent to the server.
data ClientEvent =
    Connect !SuggestedPlayerName !ClientType
  | Disconnect
  | EnteredState !StateValue
  | ExitedState !StateValue
  | WorldProposal !WorldEssence
    -- ^ In response to 'WorldRequest'
  | ChangeWallDistribution !WallDistribution
  | ChangeWorldShape !WorldShape
  | IsReady !WorldId
  -- ^ When the level's UI transition is finished.
  | Action !ActionTarget !Direction
   -- ^ A player action on an 'ActionTarget' in a 'Direction'.
  | GameEnded !GameOutcome
  | LevelWon
  | Say !Text
  deriving(Generic, Show)

data ServerEvent =
    ConnectionAccepted !ClientId ![PlayerName]
  | ConnectionRefused !NoConnectReason
  | DisconnectionAccepted
  | EnterState !StateValue
  | ExitState !StateValue
  | PlayerInfo !PlayerName !PlayerNotif
  | GameInfo !GameNotif
  | WorldRequest !WorldSpec
  -- ^ Sent to 'WorldCreator's, which should respond with a 'WorldProposal'.
  | ChangeLevel !LevelSpec !WorldEssence
    -- ^ Triggers a UI transition between the previous (if any) and the next level.
  | GameEvent !GameStep
  | Error !String
  -- ^ to have readable errors, we send errors to the client, so that 'error' can be executed in the client
  deriving(Generic, Show)

-- | 'PeriodicMotion' aggregates the accelerations of all ships during a game period.
data GameStep =
    PeriodicMotion {
    _shipsAccelerations :: ![(ShipId, Coords Vel)]
  , _shipsLostArmor :: ![ShipId]
}
  | LaserShot !ShipId !Direction
  deriving(Generic, Show)

instance Binary GameStep

instance Binary ClientEvent
instance Binary ServerEvent

instance WebSocketsData ClientEvent where
  fromDataMessage (Text t _) =
    error $ "Text was received for ClientEvent : " ++ unpack (decodeUtf8 t)
  fromDataMessage (Binary bytes) = Bin.decode bytes
  fromLazyByteString = Bin.decode
  toLazyByteString = Bin.encode
  {-# INLINABLE fromDataMessage #-}
  {-# INLINABLE fromLazyByteString #-}
  {-# INLINABLE toLazyByteString #-}
instance WebSocketsData ServerEvent where
  fromDataMessage (Text t _) =
    error $ "Text was received for ServerEvent : " ++ unpack (decodeUtf8 t)
  fromDataMessage (Binary bytes) = Bin.decode bytes
  fromLazyByteString = Bin.decode
  toLazyByteString = Bin.encode
  {-# INLINABLE fromDataMessage #-}
  {-# INLINABLE fromLazyByteString #-}
  {-# INLINABLE toLazyByteString #-}

data PlayerNotif =
    Joins
  | Leaves
  | StartsGame
  | Says !Text
  deriving(Generic, Show)
instance Binary PlayerNotif

data GameNotif =
    GameResult !GameOutcome
  deriving(Generic, Show)
instance Binary GameNotif

toTxt :: PlayerNotif -> PlayerName -> Text
toTxt Joins (PlayerName n) = "<< " <> n <> " joins the game. >>"
toTxt Leaves (PlayerName n) = "<< " <> n <> " leaves the game. >>"
toTxt StartsGame (PlayerName n) = "<< " <> n <> " starts the game. >>"
toTxt (Says t) (PlayerName n) = n <> " : " <> t

toTxt' :: GameNotif -> Text
toTxt' (GameResult (Lost reason)) = "<< The game was lost : " <> reason <> ". >>"
toTxt' (GameResult Won) = "<< The game was won! >>"

welcome :: [PlayerName] -> Text
welcome l = "Welcome! Users: " <> intercalate ", " (map (\(PlayerName n) -> n) l)

newtype SuggestedPlayerName = SuggestedPlayerName String
  deriving(Generic, Eq, Show, Binary, IsString)


data ConnectionStatus =
    NotConnected
  | Connected !ClientId
  | ConnectionFailed !NoConnectReason

data NoConnectReason =
    InvalidName !SuggestedPlayerName !Text
  deriving(Generic, Show)

instance Binary NoConnectReason


getServerNameAndPort :: Server -> (ServerName, ServerPort)
getServerNameAndPort (Local p) = (ServerName "localhost", p)
getServerNameAndPort (Distant name p) = (name, p)

newtype ServerName = ServerName String
  deriving (Show, IsString, Eq)

newtype ServerPort = ServerPort Int
  deriving (Generic, Show, Num, Integral, Real, Ord, Eq, Enum)


{- Visual representation of client events where 2 players play on the same multiplayer game:

Legend:
------
  - @Ax@ = acceleration of ship x
  - @Lx@ = laser shot of ship x
  - @.@  = end of a game period

@
        >>> time >>>
 . . . A1 . . A1 A2 L2 L1 .
              ^^^^^ ^^^^^
              |     |
              |     laser shots can't be aggregated.
              |
              accelerations can be aggregated, their order within a period is unimportant.
@

The order in which L1 L2 are handled is the order in which they are received by the server.
This is /unfair/ to the players because one player (due to network delays) could have rendered the
last period 100ms before the other, thus having a noticeable advantage over the other player.
We could be more fair by keeping track of the perceived time on the player side:

in 'ClientAction' we could store the difference between the system time of the action
and the system time at which the last motion update was presented to the player.

Hence, to know how to order close laser shots, if the ships are on the same row or column,
the server should wait a little (max. 50 ms?) to see if the other player makes a
perceptually earlier shot.
-}
