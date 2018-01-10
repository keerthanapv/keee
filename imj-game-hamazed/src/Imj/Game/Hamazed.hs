{-# LANGUAGE NoImplicitPrelude #-}

module Imj.Game.Hamazed
      ( -- * The game
        {-| In Hamazed, you are a 'BattleShip' pilot surrounded by flying 'Number's.

        Your mission is to shoot exactly the 'Number's whose sum will equate the
        current 'Level' 's /target number/.

        The higher the 'Level' (1..12), the more 'Number's are flying around (up-to 16).
        And the smaller the 'World' gets.

        Good luck !

        /Note that to adapt the keyboard layout, you can modify 'eventFromKey'./
        -}
        run
      -- * Parameters
      {-| When the game starts, the player can chose 'World' parameters:

      * 'WorldShape' : square or rectangular 'World' where the width is twice the height
      * 'WallDistribution' : Should the 'World' have walls, and what kind of walls.
      * 'ViewMode' : Should the view be centered on the 'BattleShip' or not.
       -}
      , GameParameters(..)
        -- * Game loop
        {-| Hamazed is a /synchronous/, /event-driven/ program. Its /simplified/ main loop is:

        * 'getNextDeadline'

            * \(deadline\) = the next foreseen 'Deadline'.

        * 'getEventForMaybeDeadline'

            * \(event\) =

                * a key-press occuring /before/ \(deadline\) expires
                * or the \(deadline\) event

        * 'update'

            * Update 'GameState' according to \(event\)

        * Draw and render using "Imj.Graphics.Render.Delta" to avoid
        <https://en.wikipedia.org/wiki/Screen_tearing screen tearing:

            * 'draw' : draws the game elements.
            * 'renderToScreen' : renders what was drawn to the screen.
        -}
      , getNextDeadline
      , getEventForMaybeDeadline
      , update
      , draw
        -- * Deadlines
      , Deadline(..)
      , DeadlineType(..)
        -- * Events
      , Event(..)
      , ActionTarget(..)
      , MetaAction(..)
        -- * GameState
      , GameState(..)
        -- * Environment
        {- | -}
      , module Imj.Game.Hamazed.Env
        -- * Keyboard layout
      , eventFromKey
        -- * Reexport
      , module Imj.Game.Hamazed.World
      , UIAnimation(..)
      ) where

import           Imj.Prelude

import           Imj.Game.Hamazed.Color
import           Imj.Game.Hamazed.Env
import           Imj.Game.Hamazed.KeysMaps
import           Imj.Game.Hamazed.Level
import           Imj.Game.Hamazed.Level.Types
import           Imj.Game.Hamazed.Loop.Draw
import           Imj.Game.Hamazed.Loop.Deadlines
import           Imj.Game.Hamazed.Loop.Event
import           Imj.Game.Hamazed.Loop.Run
import           Imj.Game.Hamazed.Loop.Timing
import           Imj.Game.Hamazed.Loop.Update
import           Imj.Game.Hamazed.Types
import           Imj.Game.Hamazed.World
