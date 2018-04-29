{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE DeriveGeneric #-}

module Imj.Client.Types
      ( EventsForClient(..)
      ) where

import           Imj.Prelude

import           Imj.Server.Types

data EventsForClient c s =
    FromClient !c
  | FromServer !(ServerEvent s)
  deriving(Generic)
instance (Server s, Show c) => Show (EventsForClient c s) where
  show (FromClient e) = show ("FromClient", e)
  show (FromServer e) = show ("FromServer", e)
