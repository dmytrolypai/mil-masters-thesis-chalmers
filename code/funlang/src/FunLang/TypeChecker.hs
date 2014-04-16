-- | Type checking module. Most of the functions follow the AST structure.
-- Built using the API from 'TypeCheckM'.
module FunLang.TypeChecker
  ( typeCheck
  , typeCheckStage
  , TypeEnv
  , initTypeEnv
  , TcError
  , prPrint
  ) where

import qualified Data.Set as Set

import FunLang.AST
import FunLang.TypeChecker.TypeCheckM
import FunLang.TypeChecker.TcError
import FunLang.BuiltIn
import FunLang.Utils

-- | Main batch entry point to the TypeChecker.
-- In the case of success returns a typed program and a type environment.
typeCheck :: SrcProgram -> Either TcError (TyProgram, TypeEnv)
typeCheck srcProgram = runTypeCheckM (tcProgram srcProgram) initTypeEnv

-- | Main staging entry point to the TypeChecker.
-- Takes a type environment to begin with. May be used for adding chunks of the
-- program and type checking them together with previously type checked chunks.
-- In the case of success returns a typed program and a type environment.
typeCheckStage :: SrcProgram -> TypeEnv -> Either TcError (TyProgram, TypeEnv)
typeCheckStage srcProgram typeEnv = runTypeCheckM (tcProgram srcProgram) typeEnv

tcProgram :: SrcProgram -> TypeCheckM TyProgram
tcProgram (Program s typeDefs funDefs) = do
  collectDefs typeDefs funDefs
  -- Type parameters and function types have been checked.
  -- Now first information about definitions is in the environment:
  -- + type names and their kinds
  -- + function names and their types
  checkMain
  mapM_ tcTypeDef typeDefs
  tyFunDefs <- mapM tcFunDef funDefs
  return $ Program s typeDefs tyFunDefs

-- | In order to be able to handle (mutually) recursive definitions, we need to
-- do an additional first pass to collect type names with their kinds and
-- function names and type signatures.
--
-- It collects:
--
-- * type names and their kinds
--
-- * function names and their types
--
-- It also does checking of type parameters and function types.
collectDefs :: [SrcTypeDef] -> [SrcFunDef] -> TypeCheckM ()
collectDefs typeDefs funDefs = do
  -- It is essential that we collect types before functions, because function
  -- types may mention defined data types.
  mapM_ collectTypeDef typeDefs
  mapM_ collectFunDef funDefs

-- | Checks if the type is already defined.
-- Checks that all type variables are distinct.
-- Adds the type name and its kind to the type environment.
collectTypeDef :: SrcTypeDef -> TypeCheckM ()
collectTypeDef (TypeDef _ srcTypeName srcTypeVars _) = do
  whenM (isTypeDefined $ getTypeName srcTypeName) $
    throwError $ TypeAlreadyDefined srcTypeName
  let typeVars = map getTypeVar srcTypeVars
  foldM_ (\tvs tv -> if tv `Set.member` tvs
                       then throwError (OtherError "Type var dup")  -- TODO
                       else return $ Set.insert tv tvs)
         Set.empty typeVars
  let kind = mkKind (length srcTypeVars)
  addType srcTypeName kind

-- | Checks if the function is already defined.
-- Checks that the specified function type is correct (well-formed,
-- well-kinded and uses types in scope).
-- Adds the function and its type to the environment.
collectFunDef :: SrcFunDef -> TypeCheckM ()
collectFunDef (FunDef _ srcFunName funSrcType _) = do
  whenM (isFunctionDefined $ getFunName srcFunName) $
    throwError $ FunctionAlreadyDefined srcFunName
  funType <- srcTypeToType funSrcType
  addFunction srcFunName funType funSrcType

-- | Program needs to have an entry point: `main : IO Unit`.
checkMain :: TypeCheckM ()
checkMain = do
  unlessM (isFunctionDefined $ FunName "main") $
    throwError MainNotDefined
  funTypeInfo <- getFunTypeInfo $ FunName "main"
  let mainType = ioType unitType
  when (ftiType funTypeInfo /= mainType) $
    throwError $ MainWrongType (ftiSrcType funTypeInfo)

-- | Checks data constructors and adds them to the environment together with
-- their function types.
-- Data constructors are checked with type parameters in scope.
tcTypeDef :: SrcTypeDef -> TypeCheckM ()
tcTypeDef (TypeDef s srcTypeName srcTypeVars srcConDefs) = do
  return ()  -- TODO

-- | Checks that constructor fields are correct (well-formed, well-kinded and
-- use types in scope).
-- Constructs a function type for the data constructor.
-- Adds the constructor with its type to the environment.
tcConDef :: SrcConDef -> TypeCheckM ()
tcConDef (ConDef s conName conFields) = do
  return ()  -- TODO

-- | Checks all function equations and their consistency (TODO).
-- Returns type checked and annotated function definition.
tcFunDef :: SrcFunDef -> TypeCheckM TyFunDef
tcFunDef (FunDef s srcFunName funSrcType srcFunEqs) = do
  let funName = getFunName srcFunName
  funType <- srcTypeToType funSrcType
  tyFunEqs <- mapM (tcFunEq funName funType) srcFunEqs
  return $ FunDef s srcFunName funSrcType tyFunEqs

-- | Checks that function equation belongs to the correct function definition.
-- Checks equation body.
-- Checks that the type of the body is consistent with the specified function
-- type.
-- Returns type checked and annotated function equation.
tcFunEq :: FunName -> Type -> SrcFunEq -> TypeCheckM TyFunEq
tcFunEq funName funType (FunEq s srcFunName patterns srcBodyExpr) = do
  when (getFunName srcFunName /= funName) $
    throwError $ OtherError "Wrong fun name in eq"  -- TODO
  (tyBodyExpr, bodyType) <- tcExpr srcBodyExpr
  when (bodyType /= funType) $
    throwError $ OtherError "Wrong type of body"  -- TODO
  return $ FunEq s srcFunName [] tyBodyExpr

-- | Annotates variable occurences with their types.
-- Returns a type checked and annotated expression together with its type.
tcExpr :: SrcExpr -> TypeCheckM (TyExpr, Type)
tcExpr srcExpr =
  case srcExpr of
    LitE srcLit -> return (LitE srcLit, typeOfLiteral $ getLiteral srcLit)
    VarE s var -> undefined
    LambdaE s varBinders expr -> undefined

typeOfLiteral :: Literal -> Type
typeOfLiteral UnitLit      = unitType
typeOfLiteral IntLit    {} = intType
typeOfLiteral FloatLit  {} = floatType
typeOfLiteral StringLit {} = stringType

-- | Returns a type of type checked and annotated expression.
-- Purely local process.
typeOf :: TyExpr -> Type
typeOf (LitE {}) = undefined

-- | Annotates variable occurences with their types.
-- Returns a type checked and annotated statement together with its type.
tcStmt :: SrcStmt -> TypeCheckM (TyStmt, Type)
tcStmt = undefined

-- | Transforms a source representation of type into an internal one.
-- Checks if the type is well-formed, well-kinded and uses types in scope.
--
-- Type is ill-formed when something other than a type constructor or
-- another type application or parenthesised type is on the left-hand side of
-- the type application.
--
-- Type is ill-kinded when a type constructor is not fully applied. There is
-- also a check that type variables are not applied (they are of kind *).
--
-- 'SrcTyCon' which may stand for a type variable or a type constructor is
-- transformed accordingly (if it is in scope). Kind checking is done at this
-- point.
-- 'SrcTyForAll' adds type variable to the scope after checking whether it
-- shadows existing types or type variables in scope.
-- The most interesting case is 'SrcTyApp', which is binary as opposed to the
-- 'TyApp'. We recursively dive into the left-hand side of the application and
-- collect transformed right-hand sides to the arguments list until we hit the
-- 'SrcTyCon'. There is a kind construction going to, see inline comments.
srcTypeToType :: SrcType -> TypeCheckM Type
srcTypeToType = srcTypeToType' Set.empty StarK
  where
    -- We keep a set of type variables which are currently in scope.
    -- During the transformation we construct a kind that a type constructor
    -- should have, see 'SrcTyApp' case where it is modified and 'SrcTyCon'
    -- case where it is checked.
    srcTypeToType' :: Set.Set TypeVar -> Kind -> SrcType -> TypeCheckM Type
    srcTypeToType' typeVars kind (SrcTyCon srcTypeName) = do
      let typeName = getTypeName srcTypeName
          typeVar = typeNameToTypeVar typeName
      ifM (isTypeDefined typeName)
        (do dataTypeInfo <- getDataTypeInfo typeName
            when (dtiKind dataTypeInfo /= kind) $
              throwError $ OtherError "Ill-kinded"  -- TODO
            return $ TyApp typeName [])
        (if typeVar `Set.member` typeVars
           then return $ TyVar typeVar
           else throwError $ OtherError "TypeNotDefined srcTypeName")  -- TODO

    srcTypeToType' typeVars kind st@(SrcTyApp _ stl str) = handleTyApp st stl str kind []
      where handleTyApp stApp st1 st2 k args =
            -- stApp is the whole SrcTyApp - used for error message
            -- st1 and st2 are components of the type application
            -- k is the kind that a type constructor should have
            -- in args we collect the arguments for the internal representation
              case st1 of
                sTyCon@(SrcTyCon srcTypeName) -> do
                  -- type constructor is on the left-hand side of the
                  -- application, it should have extra * in the kind (on the
                  -- left) in order for the type to be well-kinded.
                  tyConOrVar <- srcTypeToType' typeVars (StarK :=>: k) sTyCon
                  when (isTypeVar tyConOrVar) $
                    throwError $ OtherError "Type vars are of kind *"  -- TODO
                  let typeName = getTyAppTypeName tyConOrVar  -- should not fail
                  -- start from kind *, it is another type constructor (another application)
                  t2 <- srcTypeToType' typeVars StarK st2
                  return $ TyApp typeName (t2 : args)
                stApp'@(SrcTyApp _ st1' st2') -> do
                  -- start from kind *, it is another type constructor (another application)
                  t2 <- srcTypeToType' typeVars StarK st2
                  -- one more type application on the left, add * to the kind
                  handleTyApp stApp' st1' st2' (StarK :=>: k) (t2 : args)
                -- just strip off the parens and replace the left-hand side
                SrcTyParen _ st' -> handleTyApp stApp st' st2 k args
                _ -> throwError $ IllFormedType stApp

    srcTypeToType' typeVars kind (SrcTyArrow _ st1 st2) = do
      -- type vars set and kind modifications are local to each side of the arrow
      t1 <- srcTypeToType' typeVars kind st1
      t2 <- srcTypeToType' typeVars kind st2
      return $ TyArrow t1 t2

    srcTypeToType' typeVars kind (SrcTyForAll _ srcTypeVar st) = do
      let typeVar = getTypeVar srcTypeVar
      whenM (isTypeDefined $ typeVarToTypeName typeVar) $
        throwError $ OtherError "Type var shadows existing type"  -- TODO
      when (typeVar `Set.member` typeVars) $
        throwError $ OtherError "Type var shadows existing type var"  -- TODO
      let typeVars' = Set.insert typeVar typeVars
      t <- srcTypeToType' typeVars' kind st
      return $ TyForAll typeVar t

    srcTypeToType' typeVars kind (SrcTyParen _ st) =
      srcTypeToType' typeVars kind st

