{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}

-- | Module that defines an interface for working with type annotations of the
-- AST. Note that only typed representations should be instances of
-- 'TypeAnnotated'.
module MIL.AST.TypeAnnotated where

import MIL.AST
import MIL.TypeChecker.Helpers
import MIL.TypeChecker.TypeSubstitution
import MIL.BuiltIn

-- | AST nodes for which it makes sense to have a type should be an instance of
-- the 'TypeAnnotated' type class.
-- Note: It does not handle any error cases, expressions should be well-typed.
class TypeAnnotated ast where
  getTypeOf :: ast -> Type

instance TypeAnnotated TyExpr where
  getTypeOf (LitE lit) = getTypeOf lit
  getTypeOf (VarE varBinder) = getTypeOf varBinder
  getTypeOf (LambdaE varBinder bodyExpr) =
    TyArrow (getTypeOf varBinder) (getTypeOf bodyExpr)
  getTypeOf (AppE appExpr _argExpr) =
    let TyArrow _paramType resultType = getTypeOf appExpr
    in resultType
  getTypeOf (TypeLambdaE typeVar bodyExpr) =
    let bodyType = getTypeOf bodyExpr
    in tyForAllFromList bodyType [typeVar]
  getTypeOf (TypeAppE appExpr typeArg) =
    let TyForAll typeVar forallBodyType = getTypeOf appExpr
    in (typeVar, typeArg) `substTypeIn` forallBodyType
  getTypeOf (ConNameE _conName conType) = conType
  getTypeOf (TupleE elems) = TyTuple (map getTypeOf elems)

instance TypeAnnotated Literal where
  getTypeOf UnitLit      = unitType
  getTypeOf IntLit    {} = intType
  getTypeOf FloatLit  {} = floatType
  getTypeOf CharLit   {} = charType

instance TypeAnnotated TyCaseAlt where
  getTypeOf (CaseAlt (_,e)) = getTypeOf e

instance TypeAnnotated TyPattern where
  getTypeOf (LitP lit) = getTypeOf lit
  getTypeOf (VarP tyVarBinder) = getTypeOf tyVarBinder

instance TypeAnnotated TyVarBinder where
  getTypeOf (VarBinder (_,t)) = t
