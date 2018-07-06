module Main where
----WebServer Main
import Control.Exception(finally)
import System.IO (hClose)
import System.Exit
import System.Environment

import WebServer
 
main =do
     args <- getArgs
     if null args then do print "usage: hswebserver <port-number>";exitWith $ ExitFailure 1
      else do
      let port= read $ head args
      pwrapper  port scheduler2 ---`finally` ( hClose logHandle)
