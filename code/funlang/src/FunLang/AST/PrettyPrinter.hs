{-# OPTIONS_GHC -fno-warn-orphans #-}

-- | Module containing instances of 'Pretty' for syntax tree nodes.
--
-- Note: Instances are orphaned.
--
-- Note [Precedences and associativity]:
--
-- In order to get code with parentheses right, we use pairs of `hasPrec` and
-- `hasPrecAssoc` functions. The first one is reflexive and the second one is
-- *not*. The idea is that we use `hasPrecAssoc` function on the side on which
-- an operation associates and `hasPrec` - on another. See examples in
-- `instance Pretty Type`.
module FunLang.AST.PrettyPrinter (prPrint) where

import FunLang.AST
import FunLang.AST.Helpers
import FunLang.PrettyPrinter

-- See Note [Precedences and associativity]
instance Pretty Type where
  prPrn (TyVar typeVar) = prPrn typeVar
  prPrn t@(TyArrow t1 t2) =
    prPrnParens (t1 `typeHasLowerPrec` t) t1 <+>
    text "->" <+>
    prPrnParens (t2 `typeHasLowerPrecAssoc` t) t2
  prPrn (TyApp typeName args) =
    prPrn typeName <+>
    hsep (map (\t -> prPrnParens (not $ isAtomicType t) t) args)
  prPrn (TyForAll typeVar t) = text "forall" <+> prPrn typeVar <+> text "." <+> prPrn t

-- Since 'TypeS' is a source representation of types (how a user entered them),
-- we don't need to do extra precedence and associativity handling during the
-- pretty printing. We just print it as it is. Thanks to 'SrcTyParen'.
instance Pretty (TypeS s) where
  prPrn (SrcTyCon srcTypeName) = prPrn (getTypeName srcTypeName)
  prPrn (SrcTyApp _ st1 st2) = prPrn st1 <+> prPrn st2
  prPrn (SrcTyArrow _ st1 st2) = prPrn st1 <+> text "->" <+> prPrn st2
  prPrn (SrcTyForAll _ srcTypeVar st) = text "forall" <+> prPrn (getTypeVar srcTypeVar) <+> text "." <+> prPrn st
  prPrn (SrcTyParen _ st) = parens (prPrn st)

instance Pretty Kind where
  prPrn StarK = text "*"
  prPrn (k1 :=>: k2) = prPrn k1 <+> text "=>" <+> prPrn k2  -- TODO: parens

instance Pretty Var where
  prPrn (Var varStr) = text varStr

instance Pretty TypeVar where
  prPrn (TypeVar typeVarStr) = text typeVarStr

instance Pretty TypeName where
  prPrn (TypeName typeNameStr) = text typeNameStr

instance Pretty ConName where
  prPrn (ConName conNameStr) = text conNameStr

instance Pretty FunName where
  prPrn (FunName funNameStr) = text funNameStr

