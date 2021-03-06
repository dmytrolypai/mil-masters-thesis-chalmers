-- | Helper functions for working with AST.
module OOLang.AST.Helpers where

import OOLang.AST

-- * Getters

getFunParams :: FunType t s -> [VarBinder t s]
getFunParams (FunType _ varBinders _) = varBinders

getFunReturnType :: FunType t s -> TypeS s
getFunReturnType (FunType _ _ retType) = retType

getInitOpS :: Init t s -> InitOpS s
getInitOpS (Init _ initOpS _) = initOpS

getInitExpr :: Init t s -> Expr t s
getInitExpr (Init _ _ e) = e

getFieldDeclVarName :: FieldDecl t s -> VarS s
getFieldDeclVarName (FieldDecl _ decl _) = getDeclVarName decl

getDeclVarName :: Declaration t s -> VarS s
getDeclVarName (Decl _ varBinder _ _) = getBinderVar varBinder

getDeclVarSrcType :: Declaration t s -> TypeS s
getDeclVarSrcType (Decl _ varBinder _ _) = getBinderSrcType varBinder

getBinderVar :: VarBinder t s -> VarS s
getBinderVar (VarBinder _ _ srcVar _) = srcVar

getBinderSrcType :: VarBinder t s -> TypeS s
getBinderSrcType (VarBinder _ _ _ srcType) = srcType

-- | Returns an underlying type. For Mutable A it is A, for everything else it
-- is just the type itself. Used with assignment type checking.
-- Mutable is more modifier-like than a type-like, comparing to Ref, for
-- example, that's why we have this special treatment.
getUnderType :: Type -> Type
getUnderType (TyMutable t) = t
getUnderType            t  = t

-- | For type `Maybe A` returns a type `A`.
--
-- Note: make sure that you pass 'TyMaybe'.
getMaybeUnderType :: Type -> Type
getMaybeUnderType (TyMaybe t) = t
getMaybeUnderType t = error ("getMaybeUnderType: Not a Maybe type: " ++ show t)

-- | Removes 'TyPure' on the top-level if there is one.
stripPureType :: Type -> Type
stripPureType (TyPure t) = t
stripPureType         t  = t

-- | Implementation is stolen from 'Data.List.partition'. This is a specialised
-- version of it.
partitionClassMembers :: [MemberDecl t s] -> ([FieldDecl t s], [MethodDecl t s])
partitionClassMembers = foldr selectClassMember ([], [])
  where selectClassMember member ~(fs, ms) | FieldMemberDecl fd  <- member = (fd:fs, ms)
                                           | MethodMemberDecl md <- member = (fs, md:ms)

-- * Setters

setVarBinderAnn :: VarBinder t s -> s -> VarBinder t s
setVarBinderAnn (VarBinder _ t v st) s = VarBinder s t v st

-- * Predicates

isAssignRef :: AssignOp -> Bool
isAssignRef AssignRef {} = True
isAssignRef            _ = False

-- * Synonyms

getClassName :: ClassNameS s -> ClassName
getClassName = fst

getFunName :: FunNameS s -> FunName
getFunName = fst

getMemberName :: MemberNameS s -> MemberName
getMemberName = fst

getVar :: VarS s -> Var
getVar = fst

getBinOp :: BinOpS s -> BinOp
getBinOp = fst

getAssignOp :: AssignOpS s -> AssignOp
getAssignOp = fst

getInitOp :: InitOpS s -> InitOp
getInitOp = fst

-- * Conversions

varToFunName :: Var -> FunName
varToFunName (Var varName) = FunName varName

funNameToVar :: FunName -> Var
funNameToVar (FunName funName) = Var funName

memberNameToVar :: MemberName -> Var
memberNameToVar (MemberName nameStr) = Var nameStr

memberNameToFunName :: MemberName -> FunName
memberNameToFunName (MemberName nameStr) = FunName nameStr

varToMemberName :: Var -> MemberName
varToMemberName (Var nameStr) = MemberName nameStr

funNameToMemberName :: FunName -> MemberName
funNameToMemberName (FunName nameStr) = MemberName nameStr

-- * Type predicates

-- | Entity of this type is either an already computed value or a global
-- function without arguments.
--
-- For example, function parameter of type Unit has value type (it can be only
-- unit value, since we are in a strict language) and global function main :
-- Unit has value type, but it denotes a computation returning unit, not an
-- already computed value.
isValueType :: Type -> Bool
isValueType TyArrow {} = False
isValueType _ = True

-- | It can be either a function which has type, for example Pure Int (it
-- doesn't have arguments and purely computes a value of type Int) or a
-- function with arguments like Int -> Float -> Pure Int, which takes arguments
-- and its return type signals that it is a pure function that delivers and
-- integer value.
isPureFunType :: Type -> Bool
isPureFunType (TyPure _) = True
isPureFunType (TyArrow _ t2) = isPureFunType t2
isPureFunType _ = False

isPureType :: Type -> Bool
isPureType (TyPure _) = True
isPureType _ = False

isMutableType :: Type -> Bool
isMutableType TyMutable {} = True
isMutableType            _ = False

-- | By immutable type we mean anything else than Mutable and Ref.
--
-- Note: 'isMutable' means only Mutable, not Ref.
isImmutableType :: Type -> Bool
isImmutableType TyMutable {} = False
isImmutableType TyRef     {} = False
isImmutableType            _ = True

isRefType :: Type -> Bool
isRefType TyRef {} = True
isRefType        _ = False

isMaybeType :: Type -> Bool
isMaybeType TyMaybe {} = True
isMaybeType          _ = False

-- | Checks whether it is Maybe, Mutable Maybe or Ref Maybe type.
-- Variables of these types can be uninitialised and have Nothing as a value.
hasMaybeType :: Type -> Bool
hasMaybeType TyMaybe {} = True
hasMaybeType (TyMutable (TyMaybe {})) = True
hasMaybeType (TyRef     (TyMaybe {})) = True
hasMaybeType _ = False

isAtomicType :: Type -> Bool
isAtomicType TyArrow   {} = False
isAtomicType TyPure    {} = False
isAtomicType TyMaybe   {} = False
isAtomicType TyMutable {} = False
isAtomicType TyRef     {} = False
isAtomicType            _ = True

-- * Type precedences

getTypePrec :: Type -> Int
getTypePrec TyUnit       = 3
getTypePrec TyBool       = 3
getTypePrec TyInt        = 3
getTypePrec TyFloat      = 3
getTypePrec TyString     = 3
getTypePrec TyClass   {} = 3
getTypePrec TyArrow   {} = 1
getTypePrec TyPure    {} = 2
getTypePrec TyMaybe   {} = 2
getTypePrec TyMutable {} = 2
getTypePrec TyRef     {} = 2

-- | Returns whether the first type operator has a lower precedence than the
-- second one. Convenient to use in infix form.
--
-- Note: It is reflexive: t `typeHasLowerPrec` t ==> True
typeHasLowerPrec :: Type -> Type -> Bool
typeHasLowerPrec t1 t2 = getTypePrec t1 <= getTypePrec t2

-- | Returns whether the first type operator has a lower precedence than the
-- second one. Convenient to use in infix form.
-- This version can be used with associative type operators, for example:
-- arrow, type application. See "OOLang.AST.PrettyPrinter".
--
-- Note: It is *not* reflexive: t `typeHasLowerPrecAssoc` t ==> False
typeHasLowerPrecAssoc :: Type -> Type -> Bool
typeHasLowerPrecAssoc t1 t2 = getTypePrec t1 < getTypePrec t2

-- * Parsing helpers

isClassDef :: TopDef t s -> Bool
isClassDef (TopClassDef _) = True
isClassDef               _ = False

isFunDef :: TopDef t s -> Bool
isFunDef (TopFunDef _) = True
isFunDef             _ = False

