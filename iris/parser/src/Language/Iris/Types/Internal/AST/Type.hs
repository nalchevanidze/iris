{-# LANGUAGE DeriveLift #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Language.Iris.Types.Internal.AST.Type
  ( TypeRef (..),
    TypeWrapper (..),
    Nullable (..),
    Strictness (..),
    TypeKind (..),
    Subtyping (..),
    mkTypeRef,
    mkBaseType,
    mkMaybeType,
  )
where

import Language.Iris.Rendering.RenderGQL
  ( RenderGQL (..),
    Rendering,
    render,
    renderGQL,
  )
import Language.Iris.Types.Internal.AST.Error
  ( Msg (..),
  )
import Language.Iris.Types.Internal.AST.Name
  ( TypeName,
    packName,
  )
import Language.Iris.Types.Internal.AST.OperationType
  ( OperationType (..),
  )
import qualified Data.Text.Lazy as LT
import Data.Text.Lazy.Encoding (decodeUtf8)
import Language.Haskell.TH.Syntax (Lift (..))
import Relude hiding
  ( ByteString,
    decodeUtf8,
    intercalate,
  )

-- Kind
-----------------------------------------------------------------------------------
data TypeKind
  = SCALAR
  | OBJECT (Maybe OperationType)
  | UNION
  | DATA
  | LIST
  deriving (Eq, Show, Lift)

instance RenderGQL TypeKind where
  renderGQL SCALAR = "SCALAR"
  renderGQL OBJECT {} = "OBJECT"
  renderGQL UNION = "UNION"
  renderGQL DATA = "DATA"
  renderGQL LIST = "LIST"

--  Definitions:
--     Strictness:
--        Strict: Value (Strict) Types.
--             members: {scalar, data}
--        Lazy: Resolver (lazy) Types
--             members: resolver 
class Strictness t where
  isResolverType :: t -> Bool

instance Strictness TypeKind where
  isResolverType (OBJECT _) = True
  isResolverType UNION = True
  isResolverType _ = False

-- TypeWrappers
-----------------------------------------------------------------------------------
data TypeWrapper
  = TypeList !TypeWrapper !Bool
  | BaseType !Bool
  deriving (Show, Eq, Lift)

mkBaseType :: TypeWrapper
mkBaseType = BaseType True

mkMaybeType :: TypeWrapper
mkMaybeType = BaseType False

-- If S is a subtype of T, "S <: T"
-- A is a subtype of B, then all terms of type A also have type B.
-- type B = Int | Null
-- type A = Int
-- A <: B
--
-- interface A { a: String }
--
-- type B implements A { a: String!}
--
-- type B is subtype of A since :  {String} ⊂ {String, null}
--
-- interface A { a: String }
--
-- type B implements A { a: String }
--
-- type B is not subtype of A since :  {String, null} ⊂ {String}
--
-- type A = { T, Null}
-- type B = T
-- type B is subtype of A since :  {T} ⊂ {T, Null}
-- type B is Subtype if B since: {T} ⊂ {T}
class Subtyping t where
  isSubtype :: t -> t -> Bool

instance Subtyping TypeWrapper where
  isSubtype (TypeList b nonNull1) (TypeList a nonNull2) =
    nonNull1 >= nonNull2 && isSubtype b a
  isSubtype (BaseType b) (BaseType a) = b >= a
  isSubtype b a = b == a

-- TypeRef
-------------------------------------------------------------------
data TypeRef = TypeRef
  { typeConName :: TypeName,
    typeWrappers :: TypeWrapper
  }
  deriving (Show, Eq, Lift)

mkTypeRef :: TypeName -> TypeRef
mkTypeRef typeConName = TypeRef {typeConName, typeWrappers = mkBaseType}

instance Subtyping TypeRef where
  isSubtype t1 t2 =
    typeConName t1 == typeConName t2
      && typeWrappers t1 `isSubtype` typeWrappers t2

instance RenderGQL TypeRef where
  renderGQL TypeRef {typeConName, typeWrappers} = renderWrapper typeWrappers
    where
      renderWrapper (TypeList xs isNonNull) = "[" <> renderWrapper xs <> "]" <> renderNonNull isNonNull
      renderWrapper (BaseType isNonNull) = renderGQL typeConName <> renderNonNull isNonNull

renderNonNull :: Bool -> Rendering
renderNonNull True = ""
renderNonNull False = "?"

instance Msg TypeRef where
  msg = msg . packName . LT.toStrict . decodeUtf8 . render

class Nullable a where
  isNullable :: a -> Bool
  toNullable :: a -> a

instance Nullable TypeWrapper where
  isNullable (TypeList _ nonNull) = not nonNull
  isNullable (BaseType nonNull) = not nonNull
  toNullable (TypeList t _) = TypeList t False
  toNullable BaseType {} = BaseType False

instance Nullable TypeRef where
  isNullable = isNullable . typeWrappers
  toNullable TypeRef {..} = TypeRef {typeWrappers = toNullable typeWrappers, ..}