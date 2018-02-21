{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

module Imj.Game.Hamazed.Network.Types
      ( ConnectionStatus(..)
      , NoConnectReason(..)
      , DisconnectReason(..)
      , SuggestedPlayerName(..)
      , PlayerName(..)
      , ServerOwnership(..)
      , ClientState(..)
      , StateNature(..)
      , StateValue(..)
      , ClientEvent(..)
      , ServerEvent(..)
      , Command(..)
      , ClientQueues(..)
      , Server(..)
      , ServerPort(..)
      , ServerName(..)
      , getServerNameAndPort
      , PlayerNotif(..)
      , GameNotif(..)
      , LeaveReason(..)
      , GameStep(..)
      , GameStatus(..)
      , GameStateEssence(..)
      , ShotNumber(..)
      , Operation(..)
      , applyOperations
      , toTxt
      , toTxt'
      , welcome
      ) where

import           Imj.Prelude hiding(intercalate)
import           Control.Concurrent.STM(TQueue)
import           Control.DeepSeq(NFData)
import           Data.Map.Strict(Map)
import qualified Data.Binary as Bin(encode, decode)
import           Data.List(foldl')
import           Data.Set(Set)
import           Data.String(IsString)
import           Data.Text(intercalate, pack, unpack)
import qualified Data.Text.Lazy as Lazy(unpack)
import           Data.Text.Lazy.Encoding as LazyE(decodeUtf8)
import           Network.WebSockets(WebSocketsData(..), DataMessage(..))

import           Imj.Game.Hamazed.Chat
import           Imj.Game.Hamazed.Level.Types
import           Imj.Game.Hamazed.Loop.Event.Types
import           Imj.Game.Hamazed.World.Space.Types
import           Imj.Graphics.Color.Types

-- | a Server, seen from a Client's perspective
data Server = Distant ServerName ServerPort
            | Local ServerPort
  deriving(Generic, Show)

data ServerOwnership =
    ClientOwnsServer
    -- ^ Means if client is shutdown, server is shutdown too.
  | ClientDoesntOwnServer
  deriving(Generic, Show, Eq)
instance Binary ServerOwnership

data ClientState = ClientState {-unpack sum-} !StateNature {-unpack sum-} !StateValue
  deriving(Generic, Show, Eq)

data StateNature = Ongoing | Over
  deriving(Generic, Show, Eq)
instance Binary StateNature

data StateValue =
    Excluded
    -- ^ The player is not part of the game
  | Setup
  -- ^ The player is configuring the game
  | PlayLevel !GameStatus
  -- ^ The player is playing the game
  deriving(Generic, Show, Eq)
instance Binary StateValue
instance NFData StateValue

-- | A client communicates with the server asynchronously, that-is, wrt the thread where
-- game state update and rendering occurs. Using 'TQueue' as a mean of communication
-- instead of 'MVar' has the benefit that in case of the connection being closed,
-- the main thread won't block.
data ClientQueues = ClientQueues { -- TODO Use -funbox-strict-fields to force deep evaluation of thunks when inserting in the queues
    getInputQueue :: !(TQueue ServerEvent)
  , getOutputQueue :: !(TQueue ClientEvent)
}

-- | An event generated by the client, sent to the server.
data ClientEvent =
    Connect !SuggestedPlayerName {-unpack sum-} !ServerOwnership
  | Disconnect
  -- ^ The client is shutting down. Note that for clients that are 'ClientOwnsServer',
  -- this also gracefully shutdowns the server.
  | ExitedState {-unpack sum-} !StateValue
  | WorldProposal {-# UNPACK #-} !WorldEssence
    -- ^ In response to 'WorldRequest'
  | CurrentGameState {-# UNPACK #-} !GameStateEssence
    -- ^ In response to ' CurrentGameStateRequest'
  | ChangeWallDistribution {-unpack sum-} !WallDistribution
  | ChangeWorldShape {-unpack sum-} !WorldShape
  | IsReady {-# UNPACK #-} !WorldId
  -- ^ When the level's UI transition is finished.
  | Action {-unpack sum-} !ActionTarget {-unpack sum-} !Direction
   -- ^ A player action on an 'ActionTarget' in a 'Direction'.
  | LevelEnded {-unpack sum-} !LevelOutcome
  | RequestCommand {-unpack sum-} !Command
  -- ^ A Client wants to run a command, in response the server either sends 'CommandError'
  -- or 'RunCommand'
  deriving(Generic, Show)
instance Binary ClientEvent
data ServerEvent =
    ConnectionAccepted {-# UNPACK #-} !ClientId
  | ListPlayers !(Map ShipId PlayerName)
  | ConnectionRefused {-# UNPACK #-} !NoConnectReason
  | Disconnected {-unpack sum-} !DisconnectReason
  | EnterState {-unpack sum-} !StateValue
  | ExitState {-unpack sum-} !StateValue
  | PlayerInfo {-# UNPACK #-} !ClientId {-unpack sum-} !PlayerNotif
  | GameInfo {-unpack sum-} !GameNotif
  | WorldRequest {-# UNPACK #-} !WorldSpec
  -- ^ Upon reception, the client should respond with a 'WorldProposal'.
  | ChangeLevel {-# UNPACK #-} !LevelEssence {-# UNPACK #-} !WorldEssence
  -- ^ Triggers a UI transition between the previous (if any) and the next level.
  | CurrentGameStateRequest
  -- ^ (reconnection scenario) Upon reception, the client should respond with a 'CurrentGameState'.
  | PutGameState {-# UNPACK #-} !GameStateEssence
  -- ^ (reconnection scenario) Upon reception, the client should set its gamestate accordingly.
  | GameEvent {-unpack sum-} !GameStep
  | CommandError {-unpack sum-} !Command {-# UNPACK #-} !Text
  -- ^ The command cannot be run, with a reason.
  | RunCommand {-# UNPACK #-} !ShipId {-unpack sum-} !Command
  -- ^ The server validated the use of the command, now it must be executed.
  | Error !String
  -- ^ to have readable errors, we send errors to the client, so that 'error' can be executed in the client
  deriving(Generic, Show)
instance Binary ServerEvent
instance WebSocketsData ClientEvent where
  fromDataMessage (Text t _) =
    error $ "Text was received for ClientEvent : " ++ Lazy.unpack (LazyE.decodeUtf8 t)
  fromDataMessage (Binary bytes) = Bin.decode bytes
  fromLazyByteString = Bin.decode
  toLazyByteString = Bin.encode
  {-# INLINABLE fromDataMessage #-}
  {-# INLINABLE fromLazyByteString #-}
  {-# INLINABLE toLazyByteString #-}
instance WebSocketsData ServerEvent where
  fromDataMessage (Text t _) =
    error $ "Text was received for ServerEvent : " ++ Lazy.unpack (LazyE.decodeUtf8 t)
  fromDataMessage (Binary bytes) = Bin.decode bytes
  fromLazyByteString = Bin.decode
  toLazyByteString = Bin.encode
  {-# INLINABLE fromDataMessage #-}
  {-# INLINABLE fromLazyByteString #-}
  {-# INLINABLE toLazyByteString #-}

data Command =
    AssignName {-# UNPACK #-} !PlayerName
  | PutShipColor {-# UNPACK #-} !(Color8 Foreground)
  | Says {-# UNPACK #-} !Text
  deriving(Generic, Show, Eq)
instance Binary Command

data GameStateEssence = GameStateEssence {
    _essence :: {-# UNPACK #-} !WorldEssence
  , _shotNumbers :: ![ShotNumber]
  , _levelEssence :: {-unpack sum-} !LevelEssence
} deriving(Generic, Show)
instance Binary GameStateEssence

data ShotNumber = ShotNumber {
    _value :: {-# UNPACK #-} !Int
    -- ^ The numeric value
  , getOperation :: !Operation
  -- ^ How this number influences the current sum.
} deriving (Generic, Show)
instance Binary ShotNumber

data Operation = Add | Substract
  deriving (Generic, Show)
instance Binary Operation

applyOperations :: [ShotNumber] -> Int
applyOperations =
  foldl' (\v (ShotNumber n op) ->
            case op of
              Add -> v + n
              Substract -> v - n) 0
-- | 'PeriodicMotion' aggregates the accelerations of all ships during a game period.
data GameStep =
    PeriodicMotion {
    _shipsAccelerations :: ![(ShipId, Coords Vel)]
  , _shipsLostArmor :: ![ShipId]
}
  | LaserShot {-# UNPACK #-} !ShipId {-unpack sum-} !Direction
  deriving(Generic, Show)
instance Binary GameStep

data GameStatus =
    New
  | Running
  | Paused !(Set ShipId)
  -- ^ with the list of disconnected clients
  deriving(Generic, Show, Eq)
instance Binary GameStatus
instance NFData GameStatus

data ConnectionStatus =
    NotConnected
  | Connected {-# UNPACK #-} !ClientId
  | ConnectionFailed {-# UNPACK #-} !NoConnectReason

data NoConnectReason =
    InvalidName !SuggestedPlayerName {-# UNPACK #-} !Text
  deriving(Generic, Show)
instance Binary NoConnectReason

data DisconnectReason =
    BrokenClient {-# UNPACK #-} !Text
    -- ^ One client is disconnected because its connection is unusable.
  | ClientShutdown
    -- ^ One client is disconnected because it decided so.
  | ServerShutdown {-# UNPACK #-} !Text
  -- ^ All clients are disconnected.
  deriving(Generic)
instance Binary DisconnectReason
instance Show DisconnectReason where
  show (ServerShutdown t) = unpack $ "Server shutdown < " <> t
  show ClientShutdown   = "Client shutdown"
  show (BrokenClient t) = unpack $ "Broken client < " <> t

data PlayerNotif =
    Joins
  | WaitsToJoin
  | Leaves {-unpack sum-} !LeaveReason
  | StartsGame
  deriving(Generic, Show)
instance Binary PlayerNotif

data LeaveReason =
    ConnectionError !Text
  | Intentional
  deriving(Generic, Show)
instance Binary LeaveReason

data GameNotif =
    LevelResult {-# UNPACK #-} !Int {-unpack sum-} !LevelOutcome
  | GameWon
  deriving(Generic, Show)
instance Binary GameNotif

toTxt :: PlayerName -> PlayerNotif -> Text
toTxt (PlayerName n) = \case
  Joins       -> n <> " joins the game."
  WaitsToJoin -> n <> " is waiting to join the game."
  StartsGame  -> n <> " starts the game."
  Leaves Intentional         -> n <> " leaves the game."
  Leaves (ConnectionError t) -> n <> ": connection error : " <> t

toTxt' :: GameNotif -> Text
toTxt' (LevelResult n (Lost reason)) =
  "- Level " <> pack (show n) <> " was lost : " <> reason <> "."
toTxt' (LevelResult n Won) =
  "- Level " <> pack (show n) <> " was won!"
toTxt' GameWon =
  "- The game was won! Congratulations! "

welcome :: [PlayerName] -> Text
welcome l = "Welcome! Users: " <> intercalate ", " (map (\(PlayerName n) -> n) l)

newtype SuggestedPlayerName = SuggestedPlayerName String
  deriving(Generic, Eq, Show, Binary, IsString)


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
