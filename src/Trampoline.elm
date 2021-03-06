module Trampoline exposing (..)

import Fuel exposing (Gas, Fueled, RunResult(..), run, andThen, return, burn, mkEngine)

import Browser
import Html exposing (..)
import Html.Events exposing (onClick)
import Process
import Task
import Time

type Msg = Go | Refuel Gas | Stop | Tick Time.Posix
type State a = Inert | Running Gas (Fueled a) | Stopped Gas (Fueled a) | Finished a
type alias Model a =
  { state : State a
  , time : Time.Posix
  }

-- There's a careful interplay between pauseTime and refuelAmount.
--
-- Make pauseTime too low and no other events get to run... so you can't stop your computation. Bad news.
-- Make pauseTime too high and your fueled computation runs too slowly.
--
-- Make refuelAmount too low and your fueled computation runs too slowly.
-- Make refuelAmount too high and your event loop might get unresponsive.
refuelCmd : Gas -> Float -> Cmd Msg
refuelCmd refuelAmount pauseTime = Task.perform (\() -> Refuel refuelAmount) (Process.sleep pauseTime)

defaultRefuel : Cmd Msg
defaultRefuel = refuelCmd 5 20.0

doGo : (b -> Fueled a) -> b -> Model a -> (Model a, Cmd Msg)
doGo engineFun arg model =
    case model.state of
        Inert -> ({ model | state = Running 0 (engineFun arg) }, defaultRefuel)
        Finished n -> (model, Cmd.none)
        Running used engine -> (model, Cmd.none)
        Stopped used engine -> ({ model | state = Running used engine }, defaultRefuel)

doRefuel : Model a -> Gas -> (Model a, Cmd Msg)
doRefuel model gas =
    case model.state of
        Inert -> (model, Cmd.none)
        Finished n -> (model, Cmd.none)
        Running used engine -> 
            let (tank, res) = run engine gas in
            case res of 
                OutOfGas newEngine -> ({ model | state = Running (used + gas) newEngine }, defaultRefuel)
                Complete v -> ({ model | state = Finished v }, Cmd.none)
        Stopped used engine -> (model, Cmd.none)

doStop : Model a -> Model a
doStop model =
    case model.state of
        Inert -> model
        Finished n -> model
        Running used engine -> { model | state = Stopped used engine }
        Stopped used engine -> model

-- sample main tying it together
main = Browser.element 
    { init = \() -> ({ state = Inert, time = Time.millisToPosix 0 }, Cmd.none)
    , view = \model ->
        div []
            [ case model.state of
                Inert -> button [ onClick Go ] [ text "go" ]
                Running used f -> div [] [ text "running, used gas: ", String.fromInt used |> text 
                                         , button [ onClick Stop ] [ text "stop" ]
                                         ]
                Stopped used f -> div [] [ text "stopped, used gas: ", String.fromInt used |> text 
                                         , button [ onClick Go ] [ text "resume" ]
                                         ]
                Finished n -> div [] [ text "done @ ", String.fromInt n |> text ]
            , h1 [] [ model.time |> Time.posixToMillis |> String.fromInt |> text ]
            ]
    , update = \msg model -> 
        case msg of
            Go -> doGo Fuel.betterDiverge 20 model
            Refuel gas -> doRefuel model gas
            Stop -> (doStop model, Cmd.none)
            Tick newTime -> ({ model | time = newTime }, Cmd.none)
    , subscriptions = \model -> Time.every 100 Tick
    }

