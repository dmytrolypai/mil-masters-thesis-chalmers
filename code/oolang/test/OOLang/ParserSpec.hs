-- | Parser tests.
module OOLang.ParserSpec (main, spec) where

import System.FilePath ((</>), (<.>))
import Test.Hspec
import Control.Monad (liftM2)
import Control.Applicative ((<$>))

import OOLang.AST
import OOLang.Parser
import OOLang.SrcSpan
import OOLang.TestUtils

-- | To be able to run this module from GHCi.
main :: IO ()
main = hspec spec

-- Configuration

testDir :: FilePath
testDir = "test" </> "parsertests"

successDir :: FilePath
successDir = testDir </> "success"

failureDir :: FilePath
failureDir = testDir </> "failure"

-- | Main specification function.
spec :: Spec
spec =
  describe "parseOOLang" $ do
    -- Success
    it "parses class definitions" $
      let baseName = "Classes"
          fileName = mkFileName baseName
          srcSp = mkSrcSpan fileName
          ast = Program (srcSp 1 1 9 3)
                  [ ClassDef (srcSp 1 1 3 3)
                      (ClassName "Shape", srcSp 1 7 1 11)
                      Nothing
                      [FieldMemberDecl $
                         FieldDecl (srcSp 2 3 2 18)
                           (Decl (srcSp 2 3 2 17)
                              (VarBinder (srcSp 2 3 2 17) ()
                                 (Var "x", srcSp 2 3 2 3)
                                 (SrcTyMutable (srcSp 2 7 2 17)
                                    (SrcTyInt $ srcSp 2 15 2 17)))
                              Nothing
                              False)
                           []]
                  , ClassDef (srcSp 5 1 9 3)
                      (ClassName "Circle", srcSp 5 7 5 12)
                      (Just (ClassName "Shape", srcSp 5 16 5 20))
                      [MethodMemberDecl $
                         MethodDecl (srcSp 6 3 8 5)
                           (FunDef (srcSp 6 3 8 5)
                              (FunName "area", srcSp 6 7 6 10)
                              (FunType (srcSp 6 14 6 21)
                                 []
                                 (SrcTyPure (srcSp 6 14 6 21)
                                    (SrcTyInt $ srcSp 6 19 6 21)))
                              [ExprS (srcSp 7 5 7 6)
                                 (LitE (IntLit (srcSp 7 5 7 5) () 1))])
                           []]]
                  []
      in successCase baseName ast

    it "parses function definitions" $
      let baseName = "Functions"
          fileName = mkFileName baseName
          srcSp = mkSrcSpan fileName
          ast = Program (srcSp 1 1 7 3)
                  []
                  [ FunDef (srcSp 1 1 3 3)
                      (FunName "f", srcSp 1 5 1 5)
                      (FunType (srcSp 1 9 1 71)
                         [ VarBinder (srcSp 1 9 1 17) ()
                             (Var "x", srcSp 1 10 1 10)
                             (SrcTyInt $ srcSp 1 14 1 16)
                         , VarBinder (srcSp 1 22 1 31) ()
                             (Var "y", srcSp 1 23 1 23)
                             (SrcTyBool $ srcSp 1 27 1 30)
                         , VarBinder (srcSp 1 36 1 46) ()
                             (Var "z", srcSp 1 37 1 37)
                             (SrcTyFloat $ srcSp 1 41 1 45)]
                         (SrcTyArrow (srcSp 1 51 1 71)
                            (SrcTyParen (srcSp 1 51 1 63)
                               (SrcTyArrow (srcSp 1 52 1 62)
                                 (SrcTyInt $ srcSp 1 52 1 54)
                                 (SrcTyBool $ srcSp 1 59 1 62)))
                            (SrcTyUnit $ srcSp 1 68 1 71)))
                      [ExprS (srcSp 2 3 2 7)
                         (LitE (UnitLit (srcSp 2 3 2 6) ()))]
                  , FunDef (srcSp 5 1 7 3)
                      (FunName "g", srcSp 5 5 5 5)
                      (FunType (srcSp 5 9 5 16)
                         []
                         (SrcTyPure (srcSp 5 9 5 16)
                            (SrcTyInt $ srcSp 5 14 5 16)))
                      [ExprS (srcSp 6 3 6 4)
                         (LitE (IntLit (srcSp 6 3 6 3) () 1))]]
      in successCase baseName ast

    it "parses class and function definitions together" $
      let baseName = "ClassesAndFunctions"
          fileName = mkFileName baseName
          srcSp = mkSrcSpan fileName
          ast = Program (srcSp 1 1 7 23)
                  [ ClassDef (srcSp 1 1 1 15)
                      (ClassName "Super", srcSp 1 7 1 11)
                      Nothing
                      []
                  , ClassDef (srcSp 7 1 7 23)
                      (ClassName "Child", srcSp 7 7 7 11)
                      (Just (ClassName "Super", srcSp 7 15 7 19))
                      []]
                  [FunDef (srcSp 3 1 5 3)
                     (FunName "fun", srcSp 3 5 3 7)
                     (FunType (srcSp 3 11 3 34)
                        [VarBinder (srcSp 3 11 3 26) ()
                           (Var "f", srcSp 3 12 3 12)
                           (SrcTyArrow (srcSp 3 16 3 25)
                              (SrcTyInt $ srcSp 3 16 3 18)
                              (SrcTyInt $ srcSp 3 23 3 25))]
                        (SrcTyUnit $ srcSp 3 31 3 34))
                     [ExprS (srcSp 4 3 4 7)
                        (LitE (UnitLit (srcSp 4 3 4 6) ()))]]
      in successCase baseName ast

    it "parses types" $
      let baseName = "Types"
          fileName = mkFileName baseName
          srcSp = mkSrcSpan fileName
          ast = Program (srcSp 1 1 6 3)
                  []
                  [FunDef (srcSp 1 1 6 3)
                     (FunName "fun", srcSp 1 5 1 7)
                     (FunType (srcSp 1 11 4 39)
                        []
                        (SrcTyArrow (srcSp 1 11 4 39)
                           (SrcTyParen (srcSp 1 11 1 22)
                             (SrcTyArrow (srcSp 1 12 1 21)
                                (SrcTyInt $ srcSp 1 12 1 14)
                                (SrcTyInt $ srcSp 1 19 1 21)))
                           (SrcTyArrow (srcSp 2 11 4 39)
                              (SrcTyMutable (srcSp 2 11 2 47)
                                 (SrcTyParen (srcSp 2 19 2 47)
                                    (SrcTyMaybe (srcSp 2 20 2 46)
                                       (SrcTyParen (srcSp 2 26 2 46)
                                          (SrcTyPure (srcSp 2 27 2 45)
                                             (SrcTyParen (srcSp 2 32 2 45)
                                                (SrcTyArrow (srcSp 2 33 2 44)
                                                   (SrcTyBool $ srcSp 2 33 2 36)
                                                   (SrcTyBool $ srcSp 2 41 2 44))))))))
                              (SrcTyArrow (srcSp 3 11 4 39)
                                 (SrcTyRef (srcSp 3 11 3 18)
                                    (SrcTyBool $ srcSp 3 15 3 18))
                                 (SrcTyRef (srcSp 4 11 4 39)
                                    (SrcTyParen (srcSp 4 15 4 39)
                                       (SrcTyArrow (srcSp 4 16 4 38)
                                          (SrcTyMaybe (srcSp 4 16 4 25)
                                             (SrcTyBool $ srcSp 4 22 4 25))
                                          (SrcTyMaybe (srcSp 4 30 4 38)
                                             (SrcTyInt $ srcSp 4 36 4 38)))))))))
                     [ExprS (srcSp 5 3 5 7)
                        (LitE (UnitLit (srcSp 5 3 5 6) ()))]]
      in successCase baseName ast

    it "parses declaration and assignment statements" $
      let baseName = "DeclAssignStatements"
          fileName = mkFileName baseName
          srcSp = mkSrcSpan fileName
          ast = Program (srcSp 1 1 8 3)
                  []
                  [FunDef (srcSp 1 1 8 3)
                     (FunName "fun", srcSp 1 5 1 7)
                     (FunType (srcSp 1 11 1 14)
                        []
                        (SrcTyUnit $ srcSp 1 11 1 14))
                     [ DeclS (srcSp 2 3 2 18)
                         (Decl (srcSp 2 3 2 17)
                            (VarBinder (srcSp 2 3 2 17) ()
                               (Var "x", srcSp 2 3 2 3)
                               (SrcTyMutable (srcSp 2 7 2 17)
                                  (SrcTyInt $ srcSp 2 15 2 17)))
                            Nothing
                            False)
                     , DeclS (srcSp 3 3 3 14)
                         (Decl (srcSp 3 3 3 13)
                            (VarBinder (srcSp 3 3 3 9) ()
                               (Var "y", srcSp 3 3 3 3)
                               (SrcTyInt $ srcSp 3 7 3 9))
                            (Just $ Init (srcSp 3 11 3 13)
                               (InitEqual, srcSp 3 11 3 11)
                               (LitE (IntLit (srcSp 3 13 3 13) () 1)))
                            False)
                     , DeclS (srcSp 4 3 4 23)
                         (Decl (srcSp 4 3 4 22)
                            (VarBinder (srcSp 4 3 4 17) ()
                               (Var "z", srcSp 4 3 4 3)
                               (SrcTyMutable (srcSp 4 7 4 17)
                                  (SrcTyInt $ srcSp 4 15 4 17)))
                            (Just $ Init (srcSp 4 19 4 22)
                               (InitMut, srcSp 4 19 4 20)
                               (LitE (IntLit (srcSp 4 22 4 22) () 1)))
                            False)
                     , AssignS (srcSp 5 3 5 9)
                         (AssignMut, srcSp 5 5 5 6)
                         (VarE (srcSp 5 3 5 3) () (Var "x") False)
                         (LitE (IntLit (srcSp 5 8 5 8) () 2))
                         False
                     , DeclS (srcSp 6 3 6 22)
                         (Decl (srcSp 6 3 6 21)
                            (VarBinder (srcSp 6 3 6 13) ()
                               (Var "r", srcSp 6 3 6 3)
                               (SrcTyRef (srcSp 6 7 6 13)
                                  (SrcTyInt $ srcSp 6 11 6 13)))
                            (Just $ Init (srcSp 6 15 6 21)
                               (InitEqual, srcSp 6 15 6 15)
                               (NewRefE (srcSp 6 17 6 21) ()
                                  (LitE (IntLit (srcSp 6 21 6 21) () 1))))
                            False)
                     , AssignS (srcSp 7 3 7 9)
                         (AssignRef, srcSp 7 5 7 6)
                         (VarE (srcSp 7 3 7 3) () (Var "r") False)
                         (LitE (IntLit (srcSp 7 8 7 8) () 2))
                         False]]
      in successCase baseName ast

    it "parses control flow statements" $
      let baseName = "ControlStatements"
          fileName = mkFileName baseName
          srcSp = mkSrcSpan fileName
          ast = Program (srcSp 1 1 14 3)
                  []
                  [FunDef (srcSp 1 1 14 3)
                     (FunName "fun", srcSp 1 5 1 7)
                     (FunType (srcSp 1 11 1 14)
                        []
                        (SrcTyUnit $ srcSp 1 11 1 14))
                     [ WhenS (srcSp 2 3 5 6)
                         (VarE (srcSp 2 8 2 8) () (Var "b") False)
                         [ExprS (srcSp 3 5 3 9)
                            (LitE (UnitLit (srcSp 3 5 3 8) ()))]
                         []
                     , WhileS (srcSp 6 3 7 6)
                         (LitE (BoolLit (srcSp 6 9 6 12) () True))
                         []
                     , TryS (srcSp 8 3 13 6)
                         [ThrowS (srcSp 9 5 9 16) () (SrcTyInt $ srcSp 9 12 9 14)]
                         [ExprS (srcSp 11 5 11 6)
                            (LitE $ IntLit (srcSp 11 5 11 5) () 1)]
                         []]]
      in successCase baseName ast

    it "parses expressions" $
      let baseName = "Expressions"
          fileName = mkFileName baseName
          srcSp = mkSrcSpan fileName
          ast = Program (srcSp 1 1 5 3)
                  []
                  [FunDef (srcSp 1 1 5 3)
                     (FunName "fun", srcSp 1 5 1 7)
                     (FunType (srcSp 1 11 1 14)
                        []
                        (SrcTyUnit $ srcSp 1 11 1 14))
                     [ ExprS (srcSp 2 3 2 34)
                         (BinOpE (srcSp 2 3 2 33) ()
                            (App, srcSp 2 14 2 14)
                            (BinOpE (srcSp 2 3 2 13) ()
                               (App, srcSp 2 9 2 9)
                               (BinOpE (srcSp 2 3 2 8) ()
                                  (App, srcSp 2 4 2 4)
                                  (VarE (srcSp 2 3 2 3) () (Var "f") False)
                                  (LitE (UnitLit (srcSp 2 5 2 8) ()))
                                  False)
                               (LitE (BoolLit (srcSp 2 10 2 13) () True))
                               False)
                            (DerefE (srcSp 2 15 2 33) ()
                               (ParenE (srcSp 2 16 2 33)
                                  (BinOpE (srcSp 2 17 2 32) ()
                                     (App, srcSp 2 28 2 28)
                                     (BinOpE (srcSp 2 17 2 27) ()
                                        (App, srcSp 2 26 2 26)
                                        (BinOpE (srcSp 2 17 2 25) ()
                                           (App, srcSp 2 18 2 18)
                                           (VarE (srcSp 2 17 2 17) () (Var "h") False)
                                           (LitE (StringLit (srcSp 2 19 2 25) () "Hello"))
                                           False)
                                        (LitE (IntLit (srcSp 2 27 2 27) () 1))
                                        False)
                                     (LitE (FloatLit (srcSp 2 29 2 32) () 0.01 "0.01"))
                                     False)))
                            False)
                     , ExprS (srcSp 3 3 3 28)
                         (JustE (srcSp 3 3 3 27) ()
                            (LitE (NothingLit (srcSp 3 8 3 27) ()
                               (SrcTyMaybe (srcSp 3 17 3 26)
                                  (SrcTyUnit $ srcSp 3 23 3 26)))))
                     , ExprS (srcSp 4 3 4 8)
                         (NewRefE (srcSp 4 3 4 7) ()
                            (LitE (IntLit (srcSp 4 7 4 7) () 1)))]]
      in successCase baseName ast

    it "parses class expressions" $
      let baseName = "ClassExpressions"
          fileName = mkFileName baseName
          srcSp = mkSrcSpan fileName
          ast = Program (srcSp 1 1 5 3)
                  []
                  [FunDef (srcSp 1 1 5 3)
                     (FunName "fun", srcSp 1 5 1 7)
                     (FunType (srcSp 1 11 1 14)
                        []
                        (SrcTyUnit $ srcSp 1 11 1 14))
                     [ ExprS (srcSp 2 3 2 20)
                         (BinOpE (srcSp 2 3 2 19) ()
                            (App, srcSp 2 18 2 18)
                            (MemberAccessE (srcSp 2 3 2 17) ()
                               (ParenE (srcSp 2 3 2 12)
                                  (BinOpE (srcSp 2 4 2 11) ()
                                     (App, srcSp 2 10 2 10)
                                     (MemberAccessE (srcSp 2 4 2 9) ()
                                        (VarE (srcSp 2 4 2 4) () (Var "x") False)
                                        (MemberName "fun1", srcSp 2 6 2 9) False)
                                     (LitE (IntLit (srcSp 2 11 2 11) () 1))
                                     False))
                               (MemberName "fun2", srcSp 2 14 2 17) False)
                            (LitE (IntLit (srcSp 2 19 2 19) () 2))
                            False)
                     , ExprS (srcSp 3 3 3 17)
                         (BinOpE (srcSp 3 3 3 16) ()
                            (App, srcSp 3 15 3 15)
                            (MemberAccessMaybeE (srcSp 3 3 3 14) ()
                               (VarE (srcSp 3 3 3 3) () (Var "x") False)
                               (MemberName "maybeFun", srcSp 3 7 3 14) False)
                            (LitE (IntLit (srcSp 3 16 3 16) () 1))
                            False)
                     , ExprS (srcSp 4 3 4 15)
                         (BinOpE (srcSp 4 3 4 14) ()
                            (App, srcSp 4 13 4 13)
                            (ClassAccessE (srcSp 4 3 4 12) ()
                               (ClassName "Object", srcSp 4 3 4 8)
                               (FunName "new", srcSp 4 10 4 12))
                            (LitE (IntLit (srcSp 4 14 4 14) () 1))
                            False)]]
      in successCase baseName ast

    it "parses binary operations" $
      let baseName = "BinOpExpressions"
          fileName = mkFileName baseName
          srcSp = mkSrcSpan fileName
          ast = Program (srcSp 1 1 4 3)
                  []
                  [FunDef (srcSp 1 1 4 3)
                     (FunName "fun", srcSp 1 5 1 7)
                     (FunType (srcSp 1 11 1 14)
                        []
                        (SrcTyUnit $ srcSp 1 11 1 14))
                     [ ExprS (srcSp 2 3 2 34)
                         (BinOpE (srcSp 2 3 2 33) ()
                            (Equal, srcSp 2 23 2 23)
                            (BinOpE (srcSp 2 3 2 21) ()
                               (Add, srcSp 2 9 2 9)
                               (BinOpE (srcSp 2 3 2 7) ()
                                  (Add, srcSp 2 5 2 5)
                                  (LitE (IntLit (srcSp 2 3 2 3) () 1))
                                  (LitE (IntLit (srcSp 2 7 2 7) () 2))
                                  False)
                               (BinOpE (srcSp 2 11 2 21) ()
                                  (Mul, srcSp 2 19 2 19)
                                  (ParenE (srcSp 2 11 2 17)
                                     (BinOpE (srcSp 2 12 2 16) ()
                                        (Add, srcSp 2 14 2 14)
                                        (LitE (IntLit (srcSp 2 12 2 12) () 3))
                                        (LitE (IntLit (srcSp 2 16 2 16) () 4))
                                        False))
                                  (LitE (IntLit (srcSp 2 21 2 21) () 5))
                                  False)
                               False)
                            (BinOpE (srcSp 2 25 2 33) ()
                               (Mul, srcSp 2 31 2 31)
                               (BinOpE (srcSp 2 25 2 29) ()
                                  (Mul, srcSp 2 27 2 27)
                                  (LitE (IntLit (srcSp 2 25 2 25) () 2))
                                  (LitE (IntLit (srcSp 2 29 2 29) () 3))
                                  False)
                               (LitE (IntLit (srcSp 2 33 2 33) () 4))
                               False)
                            False)
                     , ExprS (srcSp 3 3 3 14)
                         (BinOpE (srcSp 3 3 3 13) ()
                            (NothingCoalesce, srcSp 3 5 3 6)
                            (VarE (srcSp 3 3 3 3) () (Var "x") False)
                            (BinOpE (srcSp 3 8 3 13) ()
                               (NothingCoalesce, srcSp 3 10 3 11)
                               (VarE (srcSp 3 8 3 8) () (Var "y") False)
                               (VarE (srcSp 3 13 3 13) () (Var "z") False)
                               False)
                            False)]]
      in successCase baseName ast

    -- Failure
    describe "gives an error message" $ do
      it "given an empty program" $
        failureCase "Empty"

      it "given a class definition with missing class name" $
        failureCase "MissingClassName"

      it "given a class definition with lower case name" $
        failureCase "ClassNameLower"

      it "given a class definition with missing end" $
        failureCase "ClassMissingEnd"

      it "given a class definition with missing super class name" $
        failureCase "MissingSuperClassName"

      it "given a function definition with missing def" $
        failureCase "FunMissingDef"

      it "given a function definition with missing name" $
        failureCase "MissingFunName"

      it "given a function definition with upper case name" $
        failureCase "FunNameUpper"

      it "given a function definition with missing type" $
        failureCase "MissingFunType"

      it "given a function definition with missing end" $
        failureCase "FunMissingEnd"

      it "given an empty function definition" $
        failureCase "EmptyFunDef"

      it "given a variable binder with missing variable name" $
        failureCase "VarBinderMissingName"

      it "given a variable binder with missing type" $
        failureCase "VarBinderMissingType"

      it "given a variable binder with unbalanced curlies" $
        failureCase "VarBinderUnbalancedCurlies"

      it "given an unparenthesised Mutable nesting" $
        failureCase "UnparenthesisedMutable"

      it "given an unparenthesised Maybe nesting" $
        failureCase "UnparenthesisedMaybe"

      it "given an ill-formed arrow type" $
        failureCase "IllFormedArrowType"

      it "given a lower case type name" $
        failureCase "TypeLowerCase"

-- Infrastructure

-- | Takes a file base name and an expected AST and performs a test (by
-- comparing showed ASTs).
successCase :: String -> SrcProgram -> IO ()
successCase baseName result = do
  input <- successRead baseName
  case parseOOLang (mkFileName baseName) input of
    Right pr -> show pr `shouldBe` show result
    Left err -> error $ prPrint err

-- | Takes a file base name and reads a source program.
successRead :: String -> IO String
successRead baseName = readFile (successDir </> mkFileName baseName)

-- | Takes a file base name and performs a test (by comparing pretty printed
-- error message).
failureCase :: String -> IO ()
failureCase baseName = do
  (input, errMsg) <- failureRead baseName
  let Left err = parseOOLang (mkFileName baseName) input
  prPrint err `shouldBe` errMsg

-- | Takes a file base name and reads a source program and expected error
-- message (from .err file).
failureRead :: String -> IO (String, String)
failureRead baseName =
  liftM2 (,) (readFile (failureDir </> mkFileName baseName))
             (dropNewLine <$> readFile (failureDir </> baseName <.> "err"))

