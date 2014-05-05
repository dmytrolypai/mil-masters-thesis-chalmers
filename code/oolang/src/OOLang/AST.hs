-- | Main AST module. Defines data types and type synonyms representing syntax
-- tree and some helper functions.
--
-- AST is parameterised. Some of the data types have only one type parameter s
-- (stands for source) and some have two - v (stands for variable) and s. The
-- reason is that variable occurences are parameterised and are represented
-- differently at different stages. For more on this look at the 'Expr' data
-- type (it is the only place where a field of type v is present). Thus, some
-- of the data types eventually contain 'Expr' (and therefore must have both v
-- and s) and some of them don't (and have only s).
--
-- In general, sometimes there are two version of the data type, one of which
-- may have S suffix. This distinction is for source representation of the
-- program (S data types) and internal representation which is used in later
-- phases (after parsing). The most important is 'Type' and 'TypeS'.
--
-- Some of the data types (which have several data constructors and/or
-- recursive) have s fields wired-in, while others if possible have a type
-- synonym for a pair where the first component is unannotated data type and
-- the second one is of type s. Look at most of the *Name data types. Note:
-- this order of v and s (as well as when used as type parameters) is chosen
-- for convenience of working with 'SrcAnnotated' type class (so that s is the
-- last type parameter).
--
-- For most of the data types there are type synonyms: Src and Ty versions.
-- Src versions exist for all data types, Ty - only for data types with two
-- type parameters.  Both use 'SrcSpan' as s and Src uses 'Var' as v (or
-- nothing at all), Ty uses 'VarTy' as v. Src variants result from parsing, Ty
-- variants result from type checking.
--
-- newtypes are used quite extensively to have a strong distinction between
-- different types of names.
module OOLang.AST where

import OOLang.SrcSpan

-- | Program:
--
-- * source annotation
--
-- * list of class definitions
--
-- * list of function definitions
--
-- Note: on the source level these two may be in any order.
data Program v s = Program s [ClassDef v s] [FunDef v s]
  deriving Show

type SrcProgram = Program Var   SrcSpan
type TyProgram  = Program VarTy SrcSpan

-- | Class definition:
--
-- * source annotation
--
-- * class name
--
-- * super class name (maybe)
--
-- * list of member declarations.
data ClassDef v s = ClassDef s (ClassNameS s) (Maybe (ClassNameS s)) [MemberDecl v s]
  deriving Show

type SrcClassDef = ClassDef Var   SrcSpan
type TyClassDef  = ClassDef VarTy SrcSpan

-- | Function definition:
--
-- * source annotation
--
-- * function name
--
-- * function type
--
-- * list of statements (body) - not empty
data FunDef v s = FunDef s (FunNameS s) (FunType s) [Stmt v s]
  deriving Show

type SrcFunDef = FunDef Var   SrcSpan
type TyFunDef  = FunDef VarTy SrcSpan

-- | Class member declaration. Either a field or a method.
data MemberDecl v s = FieldMemberDecl (FieldDecl v s)
                    | MethodMemberDecl (MethodDecl v s)
  deriving Show

type SrcMemberDecl = MemberDecl Var   SrcSpan
type TyMemberDecl  = MemberDecl VarTy SrcSpan

-- | Field declaration is just a declaration with modifiers (syntactically).
data FieldDecl v s = FieldDecl s (Declaration v s) [ModifierS s]
  deriving Show

type SrcFieldDecl = FieldDecl Var   SrcSpan
type TyFieldDecl  = FieldDecl VarTy SrcSpan

-- | Method declaration is just a function with modifiers (syntactically).
data MethodDecl v s = MethodDecl s (FunDef v s) [ModifierS s]
  deriving Show

type SrcMethodDecl = MethodDecl Var   SrcSpan
type TyMethodDecl  = MethodDecl VarTy SrcSpan

data Stmt v s = DeclS s (Declaration v s)
              | ExprS s (Expr v s)
                -- | Left-hand side can only be 'VarE' or 'MemberAccessE'.
              | AssignS s (AssignOpS s) (Expr v s) (Expr v s)
              | WhileS s (Expr v s) [Stmt v s]
              | WhenS s (Expr v s) [Stmt v s] [Stmt v s]
              | ReturnS s (Expr v s)
  deriving Show

type SrcStmt = Stmt Var   SrcSpan
type TyStmt  = Stmt VarTy SrcSpan

-- | Expression representation.
--
-- The most interesting case is 'VarE'. This is where v parameter comes from.
-- After parsing variable occurence contains only a name as a string and a
-- source annotation.  After type checking 'VarE' will have 'VarTy' at this
-- place instead of 'Var', which means that it is also annotated with the type
-- of this variable.
--
-- Function names are represented as 'VarE'.
--
-- 'ParenE' is used for better source spans and pretty printing.
data Expr v s = LitE (Literal s)
              | VarE s v
              | LambdaE s [VarBinder s] (Expr v s)  -- ^ Not empty.
              | MemberAccessE s (Expr v s) (MemberNameS s)
              | MemberAccessMaybeE s (Expr v s) (MemberNameS s)
                -- | Class access is just for new (constructor) right now.
              | ClassAccessE s (ClassNameS s) (FunNameS s)
              | ClassAccessStaticE s (ClassNameS s) (MemberNameS s)
              | NewRefE s (Expr v s)
                -- | This operator produces a value of type A from a value of
                -- type Ref A.
              | DerefE s (Expr v s)
              | BinOpE s (BinOpS s) (Expr v s) (Expr v s)
              | IfThenElseE s (Expr v s) (Expr v s) (Expr v s)
              | JustE s (Expr v s)
              | ParenE s (Expr v s)
  deriving Show

type SrcExpr = Expr Var   SrcSpan
type TyExpr  = Expr VarTy SrcSpan

-- | Literal constants.
data Literal s = UnitLit s
               | BoolLit s Bool
               | IntLit s Int
               | FloatLit s Double String  -- ^ The user string (for displaying).
               | StringLit s String
               | NothingLit s (TypeS s)
  deriving Show

type SrcLiteral = Literal SrcSpan

-- | Binary operators are factored out from 'Expr'.
data BinOp = App
           | NothingCoalesce
           | Add
           | Sub
           | Mul
           | Div
           | Equal
           | NotEq
           | Less
           | Greater
           | LessEq
           | GreaterEq
  deriving Show

type BinOpS s = (BinOp, s)
type SrcBinOp = BinOpS SrcSpan

-- | Internal representation of types. What types really represent.
-- For invariants see type transformations in the TypeChecker.
data Type = TyUnit
          | TyBool
          | TyInt
          | TyFloat
            -- | Strings are not first class citizens.
            -- They can only be used as literals.
          | TyString
          | TyClass ClassName
          | TyArrow Type Type
          | TyPure Type
          | TyMaybe Type
          | TyMutable Type
          | TyRef Type
  deriving (Show, Eq)

-- | Source representation of types. How a user entered them.
--
-- 'SrcTyParen' is used for better source spans and pretty printing.
data TypeS s = SrcTyUnit s
             | SrcTyBool s
             | SrcTyInt s
             | SrcTyFloat s
             | SrcTyClass (ClassNameS s)
             | SrcTyArrow s (TypeS s) (TypeS s)
             | SrcTyPure s (TypeS s)
             | SrcTyMaybe s (TypeS s)
             | SrcTyMutable s (TypeS s)
             | SrcTyRef s (TypeS s)
             | SrcTyParen s (TypeS s)
  deriving Show

type SrcType = TypeS SrcSpan

-- | Function type as it is represented in the source:
--
-- * source annotation
--
-- * list of parameters (var binders)
--
-- * return type
--
-- Note: used in parsing. Later will be transformed to the internal
-- representation (using 'Type').
data FunType s = FunType s [VarBinder s] (TypeS s)
  deriving Show

type SrcFunType = FunType SrcSpan

-- | Name (variable) declaration.
-- Consists of var binder and an optional initialiser.
data Declaration v s = Decl s (VarBinder s) (Maybe (Init v s))
  deriving Show

type SrcDeclaration = Declaration Var   SrcSpan
type TyDeclaration  = Declaration VarTy SrcSpan

-- | Initialiser expression. Uses different assignment operators.
data Init v s = Init s (InitOpS s) (Expr v s)
  deriving Show

type SrcInit = Init Var   SrcSpan
type TyInit  = Init VarTy SrcSpan

-- | Assignment operators are factored out.
--
-- * Mutable (<-) is for Mutable.
--
-- * Ref (:=) is used for Ref (references).
data AssignOp = AssignMut | AssignRef
  deriving Show

type AssignOpS s = (AssignOp, s)
type SrcAssignOp = AssignOpS SrcSpan

-- | Operators used in declaration statements.
--
-- * Equal is used for immutable (default) variables.
--
-- * Mutable (<-) is for Mutable.
--
-- There is no init operator for references, since they use (=).
data InitOp = InitEqual | InitMut
  deriving Show

type InitOpS s = (InitOp, s)
type SrcInitOp = InitOpS SrcSpan

-- | Modifiers are used in class member declarations.
data Modifier = Public | Private | Static
  deriving Show

type ModifierS s = (Modifier, s)
type SrcModifier = ModifierS SrcSpan

newtype Var = Var String
  deriving (Show, Eq, Ord)

type VarS s = (Var, s)
type SrcVar = VarS SrcSpan

-- | Variable annotated with its type.
newtype VarTy = VarTy (Var, Type)
  deriving Show

-- | Var binder is a pair of variable name and a type (in their source representations).
-- Used in function parameters.
data VarBinder s = VarBinder s (VarS s) (TypeS s)
  deriving Show

type SrcVarBinder = VarBinder SrcSpan

newtype ClassName = ClassName String
  deriving (Show, Eq, Ord)

type ClassNameS s = (ClassName, s)
type SrcClassName = ClassNameS SrcSpan

newtype FunName = FunName String
  deriving (Show, Eq, Ord)

type FunNameS s = (FunName, s)
type SrcFunName = FunNameS SrcSpan

-- | Denotes class field or method name.
newtype MemberName = MemberName String
  deriving Show

type MemberNameS s = (MemberName, s)
type SrcMemberName = MemberNameS SrcSpan

-- * Parsing helpers

-- | Used only in parsing to allow to mix class and function definitions and
-- then have them reordered in the AST.
data TopDef v s = TopClassDef { getClassDef :: ClassDef v s }
                | TopFunDef   { getFunDef   :: FunDef v s   }

type SrcTopDef = TopDef Var SrcSpan

