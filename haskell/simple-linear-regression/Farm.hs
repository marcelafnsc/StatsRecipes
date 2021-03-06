{-# LANGUAGE DeriveDataTypeable #-}

{-

Problem: The file farm.csv contains data on the US farm population
(millions of persons) from 1935 to 1980. Make a scatterplot of these
data and include the least-squares regression line of farm population
on year. (Moore, David S. The Basic Practice of Statistics. 4th
ed. New York: W. H. Freeman, 2007, p. 133, exercise 5.9.)

Here we use a template to generate a gnuplot script that generates the
plot, which will then be included in a LaTeX document. (I tried the
Haskell gnuplot wrapper, but it doesn't support the epslatex terminal,
and in any case this approach is actually much simpler and clearer.)

Cf. the "plot", "lm" and "abline" functions in R:
<http://www.statmethods.net/graphs/scatterplot.html>.

-}

module Main where

import System.Console.CmdArgs.Implicit
import Control.Monad (unless)
import Text.CSV.ByteString (CSV, parseCSV)
import qualified Data.ByteString as B
import qualified Data.ByteString.Lex.Double as BD
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8, decodeUtf8)
import qualified Data.Packed.Vector as Vector
import qualified Numeric.GSL.Fitting.Linear as Linear
import qualified Text.StringTemplate as Tpl

main = do
  -- Get the command line args
  args <- cmdArgs farm
  let errs = checkArgs args in
    unless (null errs) $ error (unlines errs)

  -- Read the data file
  csvStr <- B.readFile (dataFile args)
  let (xs, ys) = case parseCSV csvStr of
        Nothing -> error $ "Couldn't parse CSV file " ++ dataFile args
        Just csv -> csvToDoubles csv
        
  -- Do the calculation
  let (intercept, slope) = linearRegression xs ys
  
  -- Generate a gnuplot script
  let attrs = [ ("outputFile", outputFile args),
                ("intercept", show intercept),
                ("slope", show slope), 
                ("dataFile", dataFile args) ]
  tplStr <- B.readFile (templateFile args)
  let tpl = Tpl.newSTMP (T.unpack (decodeUtf8 tplStr))
  B.writeFile (scriptFile args)
    (encodeUtf8 (T.pack (Tpl.render (Tpl.setManyAttrib attrs tpl))))

-- Command-line option processing

data Farm = Farm { dataFile :: String,
                   templateFile :: String,
                   scriptFile :: String,
                   outputFile :: String }
          deriving (Data, Typeable, Show, Eq)
  
farm = Farm {
  dataFile = def &= explicit &= name "d" &= name "data" &= typFile
             &= help "data file in CSV format",
  templateFile = def &= explicit &= name "t" &= name "template" &= typFile
                 &= help "template file",
  scriptFile = def &= explicit &= name "s" &= name "script" &= typFile
               &= help "gnuplot script file to generate",
  outputFile = def &= explicit &= name "o" &= name "output" &= typFile
               &= help "LaTeX output file to generate" }

checkArgs :: Farm -> [String]
checkArgs args =
  ["data filename required" | null (dataFile args)] ++
  ["template filename required" | null (templateFile args)] ++
  ["script filename required" | null (scriptFile args)] ++
  ["output filename required" | null (outputFile args)]

-- Parse the numbers in the data file
csvToDoubles :: CSV -> ([Double], [Double])
csvToDoubles csv =
  foldr convRow ([], []) csv where
    convRow row (xAcc, yAcc) = case row of
      x:y:[] -> (fieldToDouble x : xAcc,
                 fieldToDouble y : yAcc)
      _ -> error "Expected two columns per row"
      where fieldToDouble field =
              case BD.readDouble field of
                Nothing -> error $ "Couldn't parse field " ++
                           T.unpack (decodeUtf8 field)
                Just (value, _) -> value

-- Fit the regression line
linearRegression :: [Double] -> [Double] -> (Double, Double)
linearRegression xs ys =
  let (intercept, slope, cov00, cov01, cov11, chiSq) =
        Linear.linear (Vector.fromList xs) (Vector.fromList ys)
  in (intercept, slope)
