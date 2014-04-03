module FunLang.ParserSpec (main, spec) where

import System.FilePath ((</>), (<.>))
import Test.Hspec
import Control.Monad (liftM2)
import Control.Applicative ((<$>))

import FunLang.AST
import FunLang.Parser
import FunLang.SrcSpan

main :: IO ()
main = hspec spec

-- Configuration

testDir :: FilePath
testDir = "test" </> "parsertests"

successDir :: FilePath
successDir = testDir </> "success"

failureDir :: FilePath
failureDir = testDir </> "failure"

spec :: Spec
spec =
  describe "parseFunLang" $ do
    -- Success
    it "parses data types" $
      let baseName = "DataTypes"
          fileName = mkFileName baseName
          srcSp = mkSrcSpan fileName
          ast = Program (srcSp 1 1 6 25)
                  [ TypeDef (srcSp 1 1 1 10)
                      (srcSp 1 6 1 6, TypeName "T")
                      []
                      [ConDef (srcSp 1 10 1 12)
                         (srcSp 1 10 1 12, ConName "MkT")
                         []]
                  , TypeDef (srcSp 3 1 3 24)
                      (srcSp 3 6 3 9, TypeName "Bool")
                      []
                      [ ConDef (srcSp 3 13 3 16)
                          (srcSp 3 13 3 16, ConName "True")
                          []
                      , ConDef (srcSp 3 20 3 24)
                          (srcSp 3 20 3 24, ConName "False")
                          []]
                  , TypeDef (srcSp 5 1 6 25)
                      (srcSp 5 6 5 11, TypeName "Either")
                      [ (srcSp 5 13 5 13, TypeVar "A")
                      , (srcSp 5 15 5 15, TypeVar "B")]
                      [ ConDef (srcSp 5 19 5 24)
                          (srcSp 5 19 5 22, ConName "Left")
                          []
                      , ConDef (srcSp 6 19 6 25)
                          (srcSp 6 19 6 23, ConName "Right")
                          []]]
                  []
      in successCase baseName ast

    -- Failure
    describe "gives an error message when" $ do
      it "given an empty program" $
        failureCase "Empty"

      it "given a program with type definition with no constructors" $
        failureCase "TypeZeroConstructors"

      it "given a program with type definition with missing equal sign" $
        failureCase "TypeMissingEqualSign"

      it "given a program with type definition with lower case type name" $
        failureCase "TypeLowerId"

-- Infrastructure

successCase :: String -> SrcProgram -> IO ()
successCase baseName result = do
  input <- successRead baseName
  let Right pr = parseFunLang (mkFileName baseName) input
  show pr `shouldBe` show result

successRead :: String -> IO String
successRead baseName = readFile (successDir </> mkFileName baseName)

failureCase :: String -> IO ()
failureCase baseName = do
  (input, errMsg) <- failureRead baseName
  let Left err = parseFunLang (mkFileName baseName) input
  prPrint err `shouldBe` errMsg

failureRead :: String -> IO (String, String)
failureRead baseName =
  liftM2 (,) (readFile (failureDir </> mkFileName baseName))
             (dropNewLine <$> readFile (failureDir </> baseName <.> "err"))
  where dropNewLine "" = ""
        dropNewLine str = let l = last str
                          in if l == '\n' || l == '\r'
                             then dropNewLine (init str)
                             else str

mkFileName :: String -> String
mkFileName baseName = baseName <.> "fl"

