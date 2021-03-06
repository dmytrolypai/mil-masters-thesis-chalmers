-- | Lexer tests.
module OOLang.LexerSpec (main, spec) where

import Test.Hspec
import Data.List (intercalate)

import OOLang.Lexer
import OOLang.SrcSpan

-- | To be able to run this module from GHCi.
main :: IO ()
main = hspec spec

-- | Main specification function.
spec :: Spec
spec =
  describe "lexer" $ do
    it "handles comments correctly" $
      map getToken
        (lexer "# this is a comment \n \
           \ class # this is a comment \n \
           \ def  ")
        `shouldBe`
      [KW_Class, KW_Def]

    it "recognises all keywords correctly" $
      map getToken
        (lexer "catch class def do else end false finally if just nothing \
              \ otherwise private public ref return \
              \ static then throw true try unit when while \
              \ Bool Float Int String Maybe Mutable Pure Ref Unit")
        `shouldBe`
      [ KW_Catch, KW_Class, KW_Def, KW_Do, KW_Else, KW_End, KW_False, KW_Finally, KW_If, KW_Just, KW_Nothing
      , KW_Otherwise, KW_Private, KW_Public, KW_Ref, KW_Return
      , KW_Static, KW_Then, KW_Throw, KW_True, KW_Try, KW_Unit, KW_When, KW_While
      , KW_TyBool, KW_TyFloat, KW_TyInt, KW_TyString, KW_TyMaybe, KW_TyMutable, KW_TyPure, KW_TyRef, KW_TyUnit
      ]

    it "recognises all symbols correctly" $
      map getToken
        (lexer "=  :  +  -  *  /  %  <  >  <=  >=  /= \
              \ =>  ->  \\  .  ::  ?  ??  <-  :=  ! \
              \ &&  ||  (  )  {  }  [  ]  ;")
        `shouldBe`
      [ Equal, Colon, Plus, Minus, Star, Slash, Percent, Less, Greater
      , LessEq, GreaterEq, NotEq, FatArrow, Arrow, Lambda, Dot, DoubleColon
      , Question, DoubleQuestion, LeftArrow, ColonEq, Bang
      , And, Or, OpenParen, CloseParen, OpenCurly, CloseCurly, OpenSquare, CloseSquare, SemiColon
      ]

    it "recognises all literals correctly" $
      map getToken
        (lexer "1  0.1  1e-2  1.0e-2  \"str\"")
        `shouldBe`
      [ IntLit 1, FloatLit 0.1 "0.1", FloatLit 0.01 "1e-2"
      , FloatLit 0.01 "1.0e-2", StringLit "str"
      ]

    it "recognises identifiers correctly" $
      map getToken
        (lexer "x C var123 Shape")
        `shouldBe`
      [ LowerId "x", UpperId "C", LowerId "var123", UpperId "Shape" ]

    it "handles source span correctly" $
      lexer "class \n   var"
        `shouldBe`
      [ (KW_Class, mkSrcSpan "NONAME" 1 1 1 5)
      , (LowerId "var", mkSrcSpan "NONAME" 2 4 2 6)
      ]

    it "shows tokens correctly" $
      intercalate " " (map (show . getToken)
        (lexer "catch class def do else end false finally if just nothing \
              \ otherwise private public ref return \
              \ static then throw true try unit when while \
              \ Bool Float Int String Maybe Mutable Pure Ref Unit \
              \ =  :  +  -  *  /  %  <  >  <=  >=  /= \
              \ =>  ->  \\  .  ::  ?  ??  <-  :=  ! \
              \ &&  ||  (  )  {  }  [  ]  ; \
              \ 1 0.1 1.0e-2 1e-2 \"str\" \
              \ x C var123 Shape"))
        `shouldBe`
      "catch class def do else end false finally if just nothing\
     \ otherwise private public ref return\
     \ static then throw true try unit when while\
     \ Bool Float Int String Maybe Mutable Pure Ref Unit\
     \ = : + - * / % < > <= >= /=\
     \ => -> \\ . :: ? ?? <- := !\
     \ && || ( ) { } [ ] ;\
     \ 1 0.1 1.0e-2 1e-2 \"str\"\
     \ x C var123 Shape"

