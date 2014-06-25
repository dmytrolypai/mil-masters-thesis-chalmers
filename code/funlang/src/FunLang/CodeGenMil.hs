{-# LANGUAGE GeneralizedNewtypeDeriving, ViewPatterns #-}

-- | Module responsible for MIL code generation.
--
-- All generated code operates in monads: Pure_M for pure computations and some
-- analogues (with more effects) for built-in monads. Basically, all
-- expressions (even the simplest ones, like literals and variables) result in
-- some sequence of binds (possibly empty) and return. We give fresh names to
-- subexpressions and introduce sequencing.
module FunLang.CodeGenMil
  ( codeGen
  ) where

import Control.Monad.Reader
import Control.Monad.State
import Control.Applicative
import Data.List (foldl')

import FunLang.AST
import FunLang.AST.TypeAnnotated
import FunLang.AST.Helpers
import FunLang.TypeChecker
import FunLang.TypeChecker.TypeEnv
import FunLang.TypeChecker.Helpers
import FunLang.BuiltIn
import FunLang.Utils
import qualified MIL.AST as MIL
import qualified MIL.BuiltIn as MIL

-- | Entry point to the code generator.
-- Takes a type checked program in FunLang and a type environment and produces
-- a program in MIL.
codeGen :: TyProgram -> TypeEnv -> MIL.Program
codeGen tyProgram typeEnv = runReaderFrom typeEnv $ evalStateTFrom 0 (runCG $ codeGenProgram tyProgram)

-- | Code generation monad. Uses 'StateT' for providing fresh variable names
-- and 'Reader' for querying the type environment.
newtype CodeGenM a = CG { runCG :: StateT NameSupply (Reader TypeEnv) a }
  deriving (Monad, MonadState NameSupply, MonadReader TypeEnv, Functor, Applicative)

-- | A counter for generating unique variable names.
type NameSupply = Int

codeGenProgram :: TyProgram -> CodeGenM MIL.Program
codeGenProgram (Program _ srcTypeDefs tyFunDefs) = do
  (milTypeDefs, milConWrappers) <- unzip <$> mapM codeGenTypeDef srcTypeDefs
  milFunDefs <- mapM codeGenFunDef tyFunDefs
  return $ MIL.Program (milTypeDefs, builtInAliasDefs, concat milConWrappers ++ milFunDefs)

-- | Code generation for data type.
-- Returns an MIL type definition and a list of wrapper functions for data
-- constructors.
-- See Note [Data constructors and purity].
codeGenTypeDef :: SrcTypeDef -> CodeGenM (MIL.TypeDef, [MIL.FunDef])
codeGenTypeDef (TypeDef _ srcTypeName srcTypeVars srcConDefs) = do
  let milTypeVars = map (typeVarMil . getTypeVar) srcTypeVars
  (milConDefs, milConWrappers) <- unzip <$> mapM codeGenConDef srcConDefs
  return (MIL.TypeDef (typeNameMil $ getTypeName srcTypeName) milTypeVars milConDefs, milConWrappers)

-- | Code generation for data constructor.
-- Returns an MIL constructor definition and a wrapper function definition.
-- See Note [Data constructors and purity].
codeGenConDef :: SrcConDef -> CodeGenM (MIL.ConDef, MIL.FunDef)
codeGenConDef (ConDef _ srcConName srcConFields) = do
  milConFields <- mapM monadSrcTypeMil srcConFields
  let conName = getConName srcConName
  milConWrapper <- codeGenConWrapper conName
  return (MIL.ConDef (conNameMil conName) milConFields, milConWrapper)

-- | See Note [Data constructors and purity].
codeGenConWrapper :: ConName -> CodeGenM MIL.FunDef
codeGenConWrapper conName = do
  conType <- asks (dcontiType . getDataConTypeInfo conName . getDataConTypeEnv)
  let conWrapperType = monadFunTypeMil conType
  let conNameExpr = MIL.ConNameE (conNameMil conName) (conTypeMil conType)
  conWrapperBody <- conWrapperMilExpr conWrapperType conNameExpr
  return (MIL.FunDef (conWrapperFunNameMil conName) conWrapperType conWrapperBody)

-- | Note [Data constructors and purity]:
--
-- There is a problem with function types of data constructors and FunLang's
-- Pure_M monad for pure computations. These function types are produced by the
-- MIL type checker, which doesn't know about Pure_M except for that there is
-- an type alias with this name is defined. Data constructors in MIL are
-- completely pure (they don't get special monadic types). They can be
-- referenced (and partially applied) from FunLang's pure functions (which are
-- not completely pure, they work inside Pure_M) and then the types don't
-- match. It would be very hard (or even impossible) to figure out the places
-- where we should do type conversions differently when referencing data
-- constructors.
--
-- Solution: Each data constructor gets its wrapper function in the generated
-- code (see 'conWrapperMilExpr'), which has a converted monadic type of the
-- constructor (with Pure_M all over the place).

-- | Generates a body for a data constructor wrapper function.
-- Takes a type of the wrapper function and an expression to begin with, which
-- also plays a role of the accumulator for the result.
--
-- It is like these clever programs that try to produce a term from a
-- polymorphic type (see also `Theorems for free`), but it is much more simple
-- and restricted. It doesn't try to handle all possible types, but only the
-- shape that data constructor types have.
conWrapperMilExpr :: MIL.Type -> MIL.Expr -> CodeGenM MIL.Expr
conWrapperMilExpr conWrapperType conAppMilExpr =
  case conWrapperType of
    MIL.TyApp (MIL.TyMonad tm) a -> MIL.ReturnE tm <$> conWrapperMilExpr a conAppMilExpr
    -- Each forall type produces a type lambda and adds a type application to
    -- the data constructor.
    MIL.TyForAll tv t ->
      MIL.TypeLambdaE tv <$> conWrapperMilExpr t (MIL.TypeAppE conAppMilExpr (MIL.TyVar tv))
    -- Each arrow type produces a lambda and adds an application to the data
    -- constructor.
    MIL.TyArrow t1 t2 -> do
      v <- newMilVar
      MIL.LambdaE (MIL.VarBinder (v, t1)) <$>
        conWrapperMilExpr t2 (MIL.AppE conAppMilExpr (MIL.VarE $ MIL.VarBinder (v, t1)))
    -- Base cases. It should be a type constructor (result).
    MIL.TyTypeCon _ -> return conAppMilExpr
    MIL.TyApp {} -> return conAppMilExpr

codeGenFunDef :: TyFunDef -> CodeGenM MIL.FunDef
codeGenFunDef (FunDef _ srcFunName _ tyFunEqs) = do
  let funName = getFunName srcFunName
  milFunType <- monadFunTypeMil <$> asks (ftiType . getFunTypeInfo funName . getFunTypeEnv)
  -- All generated code is monadic. Therefore, function types should have a
  -- monad.
  let (MIL.TyApp (MIL.TyMonad funMonad) _) = milFunType
  milFunBody <- codeGenFunEqs tyFunEqs funMonad
  return $ MIL.FunDef (funNameMil funName) milFunType milFunBody

-- | Takes function equations of the function definition and a function monad
-- and returns an MIL expression.
codeGenFunEqs :: [TyFunEq] -> MIL.TypeM -> CodeGenM MIL.Expr
codeGenFunEqs tyFunEqs funMonad = do
  funEqExprs <- mapM (codeGenExpr funMonad . getFunEqBody) tyFunEqs
  return $ fst $ head funEqExprs  -- TODO

-- | Expression code generation.
-- Takes a monad of the containing function.
-- Returns an MIL expression and its type.
codeGenExpr :: MIL.TypeM -> TyExpr -> CodeGenM (MIL.Expr, MIL.Type)
codeGenExpr funMonad tyExpr =
  let exprType = getTypeOf tyExpr in
  case tyExpr of
    LitE tyLit ->
      return ( MIL.ReturnE funMonad (MIL.LitE $ literalMil tyLit)
             , MIL.applyMonadType funMonad (typeMil exprType))

    VarE _ varType var -> do
      let funName = varToFunName var
      if isBuiltInFunction funName
        then codeGenBuiltInFunction funMonad var
        else do let milVar = varMil var
                isGlobalFunction <- asks (isFunctionDefined funName . getFunTypeEnv)
                if isGlobalFunction || isMonadType varType
                  -- TODO: it may be different monad?
                  then return ( MIL.VarE $ MIL.VarBinder (milVar, monadFunTypeMil varType)
                              , monadFunTypeMil varType)
                  else return ( MIL.ReturnE funMonad (MIL.VarE $ MIL.VarBinder (milVar, monadTypeMil varType))
                              , MIL.applyMonadType funMonad (monadTypeMil varType))

    LambdaE _ _ tyVarBinders tyBodyExpr -> do
      (milBodyExpr, milBodyType) <- codeGenExpr funMonad tyBodyExpr
      (milLambdaExpr, milLambdaType) <- foldM (\(mexpr, mtype) tvb -> do
          let varType = getTypeOf tvb
          let milVarType = monadTypeMil varType
          return ( MIL.ReturnE funMonad
                     (MIL.LambdaE (MIL.VarBinder ( varMil (getVar $ getBinderVar tvb)
                                                 , milVarType)) mexpr)
                 , MIL.applyMonadType funMonad (MIL.TyArrow milVarType mtype)))
        (milBodyExpr, milBodyType)
        (reverse tyVarBinders)
      return (milLambdaExpr, milLambdaType)

    TypeLambdaE _ _ srcTypeVars tyBodyExpr -> do
      (milBodyExpr, milBodyType) <- codeGenExpr funMonad tyBodyExpr
      return $ foldr (\tv (mexpr, mtype) ->
                   ( MIL.ReturnE funMonad (MIL.TypeLambdaE (typeVarMil tv) mexpr)
                   , MIL.applyMonadType funMonad (MIL.TyForAll (typeVarMil tv) mtype)))
                 (milBodyExpr, milBodyType)
                 (map getTypeVar srcTypeVars)

    TypeAppE _ _ tyAppExpr srcArgType -> do
      (milAppExpr, milAppExprType) <- codeGenExpr funMonad tyAppExpr
      var <- newMilVar
      let varType = MIL.getMonadResultType milAppExprType
      milTypeAppExpr <-
        MIL.LetE (MIL.VarBinder (var, varType))
          milAppExpr <$>
          (MIL.TypeAppE
             (MIL.VarE $ MIL.VarBinder (var, varType)) <$>
             monadSrcTypeMil srcArgType)
      return (milTypeAppExpr, monadFunTypeMil exprType)  -- TODO?

    -- See Note [Data constructors and purity].
    ConNameE conType srcConName -> do
      let conName = getConName srcConName
      let conWrapperType = monadFunTypeMil exprType
      return ( MIL.VarE $ MIL.VarBinder (conWrapperVarMil conName, conWrapperType)
             , conWrapperType)

    BinOpE _ resultType srcBinOp tyExpr1 tyExpr2 ->
      codeGenBinOp (getBinOp srcBinOp) tyExpr1 tyExpr2 resultType funMonad

    ParenE _ tySubExpr -> codeGenExpr funMonad tySubExpr

    DoE _ _ tyStmts -> codeGenDoBlock tyStmts funMonad

literalMil :: TyLiteral -> MIL.Literal
literalMil UnitLit {}         = MIL.UnitLit
literalMil (IntLit _ _ i)     = MIL.IntLit i
literalMil (FloatLit _ _ f _) = MIL.FloatLit f
literalMil (StringLit _ _ s)  = MIL.StringLit s

-- | Code generation of binary operations.
-- Takes a binary operation, its operands, a type of the result and a monad of
-- containing function.
-- Returns an MIL expression and its type.
codeGenBinOp :: BinOp -> TyExpr -> TyExpr -> Type -> MIL.TypeM -> CodeGenM (MIL.Expr, MIL.Type)
codeGenBinOp App tyExpr1 tyExpr2 resultType funMonad = do
  (milExpr1, milExpr1Type) <- codeGenExpr funMonad tyExpr1
  (milExpr2, milExpr2Type) <- codeGenExpr funMonad tyExpr2
  var1 <- newMilVar
  var2 <- newMilVar
  let var1Type = MIL.getMonadResultType milExpr1Type
  let var2Type = MIL.getMonadResultType milExpr2Type
  let appE = MIL.AppE (MIL.VarE $ MIL.VarBinder (var1, var1Type))
                      (MIL.VarE $ MIL.VarBinder (var2, var2Type))
  return ( MIL.LetE (MIL.VarBinder (var1, var1Type))
             milExpr1
             (MIL.LetE (MIL.VarBinder (var2, var2Type))
                milExpr2
                (if isMonadType resultType
                   then
                     let (MIL.TyApp (MIL.TyMonad resultMonad) _) = typeMil resultType in
                     if True  -- TODO: resultMonad `MIL.isMonadSuffixOf` funMonad?
                       then MIL.LiftE appE resultMonad funMonad
                       else appE
                   else appE))
         , monadFunTypeMil resultType)  -- TODO?

codeGenDoBlock :: [TyStmt] -> MIL.TypeM -> CodeGenM (MIL.Expr, MIL.Type)
codeGenDoBlock [ExprS _ tyExpr] funMonad = codeGenExpr funMonad tyExpr
-- Every expression code generation results in return.
codeGenDoBlock [ReturnS _ _ tyExpr] funMonad = codeGenExpr funMonad tyExpr
codeGenDoBlock (tyStmt:tyStmts) funMonad =
  case tyStmt of
    ExprS _ tyExpr -> do
      (milBindExpr, milBindType) <- codeGenExpr funMonad tyExpr
      (milBodyExpr, milBodyType) <- codeGenDoBlock tyStmts funMonad
      return ( MIL.LetE (MIL.VarBinder (MIL.Var "_", MIL.getMonadResultType milBindType))
                 milBindExpr milBodyExpr
             , milBodyType)

    BindS _ tyVarBinder tyExpr -> do
      (milBindExpr, milBindType) <- codeGenExpr funMonad tyExpr
      (milBodyExpr, milBodyType) <- codeGenDoBlock tyStmts funMonad
      return ( MIL.LetE (MIL.VarBinder ( varMil (getVar $ getBinderVar tyVarBinder)
                                       , MIL.getMonadResultType milBindType))
                 milBindExpr milBodyExpr
             , milBodyType)

    ReturnS _ _ tyExpr -> do
      (milBindExpr, milBindType) <- codeGenExpr funMonad tyExpr
      (milBodyExpr, milBodyType) <- codeGenDoBlock tyStmts funMonad
      return ( MIL.LetE (MIL.VarBinder (MIL.Var "_", MIL.getMonadResultType milBindType))
                 milBindExpr milBodyExpr
             , milBodyType)

-- | Built-in functions need a special treatment.
codeGenBuiltInFunction :: MIL.TypeM -> Var -> CodeGenM (MIL.Expr, MIL.Type)
codeGenBuiltInFunction funMonad funNameVar =
  case funNameVar of
    Var "printString" -> codeGenArgBuiltInFunction (MIL.FunName "print_string") funMonad
    Var "printInt"    -> codeGenArgBuiltInFunction (MIL.FunName "print_int") funMonad
    Var "printFloat"  -> codeGenArgBuiltInFunction (MIL.FunName "print_float") funMonad

    Var "readInt"     -> codeGenNoArgBuiltInFunction (MIL.FunName "read_int") funMonad
    Var "readFloat"   -> codeGenNoArgBuiltInFunction (MIL.FunName "read_float") funMonad

    -- TODO: state functions

    _ -> error (prPrint funNameVar ++ "is not a built-in function")

-- | These functions have at least on parameter, so we just return them in the
-- function monad.
codeGenArgBuiltInFunction :: MIL.FunName -> MIL.TypeM -> CodeGenM (MIL.Expr, MIL.Type)
codeGenArgBuiltInFunction milFunName funMonad = do
  let milFunNameVar = MIL.funNameToVar milFunName
      milFunType = MIL.getBuiltInFunctionType milFunName (MIL.builtInFunctions ++ builtInFunctionsMil)
  return $ ( MIL.ReturnE funMonad (MIL.VarE $ MIL.VarBinder (milFunNameVar, milFunType))
           , MIL.applyMonadType funMonad milFunType)

-- | These functions don't expect arguments. We must lift them if they are in a
-- different monad. Type checking ensured that they are in the correct monad.
codeGenNoArgBuiltInFunction :: MIL.FunName -> MIL.TypeM -> CodeGenM (MIL.Expr, MIL.Type)
codeGenNoArgBuiltInFunction milFunName funMonad = do
  let milFunNameVar = MIL.funNameToVar milFunName
      milFunType = MIL.getBuiltInFunctionType milFunName (MIL.builtInFunctions ++ builtInFunctionsMil)
      (MIL.TyApp (MIL.TyMonad resultMonad) monadResultType) = milFunType
  if (resultMonad /= funMonad)
    then return $ ( MIL.LiftE (MIL.VarE $ MIL.VarBinder (milFunNameVar, milFunType)) resultMonad funMonad
                  , MIL.applyMonadType funMonad monadResultType)
    else return $ ( MIL.VarE $ MIL.VarBinder (milFunNameVar, milFunType)
                  , MIL.applyMonadType funMonad monadResultType)

-- * Type conversions

-- | Note [Type conversion]:
--
-- There are several different versions of type conversion. Sometimes we need
-- to convert source types, in other cases, we are working with internal type
-- representation.
--
-- * 'typeMil' is the simplest one. It converts an internal type representation
-- to an MIL type. It doesn't know about generated monads (like Pure_M or
-- IO_M). It doesn't introduce any new monads, only maps built-in FunLang
-- monads to built-in MIL monads. Used for built-in functions and for some very
-- simple cases, like types of literals. Used in constructor type conversion
-- also (see 'conTypeMil').
--
-- * 'monadTypeMil' is one of the main `working horses` of the type conversion.
-- It introduces Pure_M monad for pure functions and converts built-in monads
-- to generated aliases (like IO_M, for example). It introduces Pure_M on the
-- right of function arrows and inside forall type. Used more for local things
-- and argument positions.
--
-- * 'monadFunTypeMil' introduces more monads compared to 'monadTypeMil' and is
-- used more with global function types and result positions. It puts Pure_M
-- before almost any type except for built-in FunLang monads.
--
-- * 'conTypeMil' is used for conversion of data constructor function type when
-- annotating constructor occurence. The idea is that it uses 'monadTypeMil'
-- for `fields` (left components of function arrows) and 'typeMil' for the
-- result type and for all the other types (on the top-level).
--
-- * 'monadSrcTypeMil' is basically a 'SrcType' version of 'monadTypeMil'.
--
-- * 'monadSrcFunTypeMil' is basically a 'SrcType' version of
-- 'monadFunTypeMil'.

-- | See Note [Type conversion].
-- The most interesting is the 'TyApp' transformation, because it deals with
-- monads. Type checker ensures that all type constructors are fully applied,
-- so it is safe to construct monadic types in this way (by direct pattern
-- matching), otherwise - we throw a panic.
typeMil :: Type -> MIL.Type
typeMil (TyVar typeVar) = MIL.TyVar $ typeVarMil typeVar
typeMil (TyArrow t1 t2) = MIL.TyArrow (typeMil t1) (typeMil t2)
typeMil (TyApp typeName typeArgs) =
  case (typeName, typeArgs) of
    (TypeName "IO", [ioResultType]) ->
      MIL.applyMonadType (MIL.MTyMonad MIL.IO) (typeMil ioResultType)
    (TypeName "IO", _) -> error "IO type is ill-formed"

    (TypeName "State", [_, stateResultType]) ->
      MIL.applyMonadType (MIL.MTyMonad MIL.State) (typeMil stateResultType)
    (TypeName "State", _) -> error "State type is ill-formed"

    _ -> foldl' (\mt t -> MIL.TyApp mt (typeMil t))
           (MIL.TyTypeCon $ typeNameMil typeName)
           typeArgs
typeMil (TyForAll typeVar t) = MIL.TyForAll (typeVarMil typeVar) (typeMil t)

-- | See Note [Type conversion].
monadTypeMil :: Type -> MIL.Type
monadTypeMil (TyVar typeVar) = MIL.TyVar $ typeVarMil typeVar
monadTypeMil (TyArrow t1 t2) = MIL.TyArrow (monadTypeMil t1) (monadFunTypeMil t2)
monadTypeMil (TyApp typeName typeArgs) =
  case (typeName, typeArgs) of
    (TypeName "IO", [ioResultType]) ->
      MIL.applyMonadType ioMonadMil (monadTypeMil ioResultType)
    (TypeName "IO", _) -> error "IO type is ill-formed"

    (TypeName "State", [_, stateResultType]) ->
      MIL.applyMonadType (MIL.MTyMonad MIL.State) (monadTypeMil stateResultType)
    (TypeName "State", _) -> error "State type is ill-formed"

    _ -> foldl' (\mt t -> MIL.TyApp mt (monadTypeMil t))
           (MIL.TyTypeCon $ typeNameMil typeName)
           typeArgs
monadTypeMil (TyForAll typeVar t) = MIL.TyForAll (typeVarMil typeVar) (monadFunTypeMil t)

-- | See Note [Type conversion].
monadFunTypeMil :: Type -> MIL.Type
monadFunTypeMil t@(TyApp typeName typeArgs) =
  case typeName of
    TypeName "IO" -> monadTypeMil t
    TypeName "State" -> monadTypeMil t
    _ -> MIL.applyMonadType pureMonadMil (monadTypeMil t)
monadFunTypeMil t = MIL.applyMonadType pureMonadMil (monadTypeMil t)

-- | Data constructor type conversion.
-- See Note [Type conversion].
conTypeMil :: Type -> MIL.Type
conTypeMil (TyArrow t1 t2@(TyArrow {})) = MIL.TyArrow (monadTypeMil t1) (conTypeMil t2)
conTypeMil (TyArrow t1 t2) = MIL.TyArrow (monadTypeMil t1) (typeMil t2)
conTypeMil t = typeMil t

-- | See Note [Type conversion].
-- Monadic types are transformed in different cases depending on their kind.
-- * IO and State have kind `* => *` so they are caught in 'SrcTyCon'.
monadSrcTypeMil :: SrcType -> CodeGenM MIL.Type
monadSrcTypeMil (SrcTyCon srcTypeName) =
  case getTypeName srcTypeName of
    TypeName "IO" -> return $ MIL.TyMonad ioMonadMil
    TypeName "State" -> return $ MIL.TyMonad (MIL.MTyMonad MIL.State)
    typeName -> do
      -- 'SrcTyCon' can represent both type names and type variables, so we
      -- need to distinguish between them in order to generate correct MIL
      -- code.
      dataTypeEnv <- asks getDataTypeEnv
      if isTypeDefined typeName dataTypeEnv
        then return $ MIL.TyTypeCon (typeNameMil typeName)
        else return $ MIL.TyVar (typeVarMil $ typeNameToTypeVar typeName)
monadSrcTypeMil (SrcTyApp _ st1 st2) =
  MIL.TyApp <$> monadSrcTypeMil st1 <*> monadSrcTypeMil st2
monadSrcTypeMil (SrcTyArrow _ st1 st2) =
  MIL.TyArrow <$> monadSrcTypeMil st1 <*> monadSrcFunTypeMil st2
monadSrcTypeMil (SrcTyForAll _ stv st) =
  MIL.TyForAll (typeVarMil $ getTypeVar stv) <$> monadSrcFunTypeMil st
monadSrcTypeMil (SrcTyParen _ st) = monadSrcTypeMil st

-- | See Note [Type conversion].
monadSrcFunTypeMil :: SrcType -> CodeGenM MIL.Type
monadSrcFunTypeMil t@(SrcTyCon srcTypeName) =
  case getTypeName srcTypeName of
    TypeName "IO" -> monadSrcTypeMil t
    TypeName "State" -> monadSrcTypeMil t
    _ -> MIL.applyMonadType pureMonadMil <$> monadSrcTypeMil t
monadSrcFunTypeMil st = MIL.applyMonadType pureMonadMil <$> monadSrcTypeMil st

-- * Conversion utils

typeNameMil :: TypeName -> MIL.TypeName
typeNameMil (TypeName typeNameStr) = MIL.TypeName typeNameStr

conNameMil :: ConName -> MIL.ConName
conNameMil (ConName conNameStr) = MIL.ConName conNameStr

conWrapperFunNameMil :: ConName -> MIL.FunName
conWrapperFunNameMil (ConName conNameStr) = MIL.FunName ("con_" ++ conNameStr)

conWrapperVarMil :: ConName -> MIL.Var
conWrapperVarMil (ConName conNameStr) = MIL.Var ("con_" ++ conNameStr)

funNameMil :: FunName -> MIL.FunName
funNameMil (FunName funNameStr) = MIL.FunName funNameStr

varMil :: Var -> MIL.Var
varMil (Var varStr) = MIL.Var varStr

typeVarMil :: TypeVar -> MIL.TypeVar
typeVarMil (TypeVar typeVarStr) = MIL.TypeVar typeVarStr

-- * Built-ins

builtInAliasDefs :: [MIL.AliasDef]
builtInAliasDefs =
  [ MIL.AliasDef pureMonadMilName $ MIL.TyMonad pureMonadMilType
  , MIL.AliasDef ioMonadMilName   $ MIL.TyMonad ioMonadMilType ]

-- * CodeGenM operations

newMilVar :: CodeGenM MIL.Var
newMilVar = do
  i <- get
  modify (+1)
  return $ MIL.Var ("var_" ++ show i)

