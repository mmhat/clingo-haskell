{-# LANGUAGE OverloadedStrings #-}
module Main where

import Clingo.Symbol
import Clingo.Control
import Clingo.Model
import Clingo.Statistics

import Data.Text.Lazy (fromStrict)
import Text.PrettyPrint.Leijen.Text

instance Pretty v => Pretty (StatsTree v) where
    pretty (SValue v) = pretty v
    pretty (SArray x) = vcat $ map (nest 1 . pretty . snd) x
    pretty (SMap s)   = vcat $ map (nest 1 . go) s
        where go (k,t) = text (fromStrict k) <> colon <> line 
                      <> nest 1 (pretty t)

onModel :: Model s -> IO Continue
onModel m = do
    syms <- mapM prettySymbol
        =<< modelSymbols m (selectNone { selectShown = True }) 
    putStr "Model: " >> print syms
    return Continue

main :: IO ()
main = withDefaultClingo $ \ctrl -> do
    addProgram ctrl "base" [] "a :- not b. b :- not a."
    ground ctrl [Part "base" []] Nothing
    _ <- solve ctrl (Just onModel) []
    stats <- statistics ctrl

    -- Print whole stats tree
    putStrLn "\nStatistics"
    fullTree <- subTree stats pure
    putDoc (pretty fullTree <> line)

    -- Print just the solving subtree
    putStrLn "\nSelected solving.solver statistics"
    solving <- subTree stats (atMap "solving" >=> atMap "solvers")
    putDoc (pretty solving <> line)

    -- Selecting only number of equations
    putStrLn "\nNumber of equations"
    eqs <- fromTree stats (atMap "problem" >=> atMap "lp" >=> atMap "eqs"
                           >=> value)
    putDoc (pretty eqs <> line)
