{-# OPTIONS_GHC -fno-warn-orphans #-}

-- | Module containing instances of 'Pretty' for syntax tree nodes.
--
-- Note: Instances are orphaned.
module OOLang.AST.PrettyPrinter (prPrint) where

import OOLang.AST
import OOLang.PrettyPrinter

instance Pretty Type where
  prPrn TyUnit = text "Unit"
  prPrn TyInt  = text "Int"

instance Pretty ClassName where
  prPrn (ClassName classNameStr) = text classNameStr

instance Pretty FunName where
  prPrn (FunName funNameStr) = text funNameStr
