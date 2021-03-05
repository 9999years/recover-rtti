{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE RankNTypes           #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Debug.RecoverRTTI.Util.TypeLevel (
    -- * Singletons
    Sing(..)
  , SingI(..)
  , DecidableEquality(..)
    -- * General purpose type level functions
  , Or
  , Equal
  , Elem
  , Assert
    -- * Type-level membership check
  , IsElem(..)
  , checkIsElem
    -- * Phantom type parameters
  , Phantom(..)
  , Poly(..)
  , maybePoly
  ) where

import Data.Kind
import Data.Proxy
import Data.Void
import Data.Type.Equality
import GHC.TypeLits

{-------------------------------------------------------------------------------
  Singletons
-------------------------------------------------------------------------------}

data family Sing :: k -> Type

class SingI (a :: k) where
  sing :: Sing a

class DecidableEquality k where
  decideEquality :: Sing (a :: k) -> Sing (b :: k) -> Maybe (a :~: b)

{-------------------------------------------------------------------------------
  For kind 'Type', Sing is just a proxy
-------------------------------------------------------------------------------}

data instance Sing (a :: Type) where
  SProxy :: Sing (a :: Type)

instance SingI (a :: Type) where
  sing = SProxy

{-------------------------------------------------------------------------------
  Singleton instance for type-level symbols
-------------------------------------------------------------------------------}

data instance Sing (n :: Symbol) where
  SSymbol :: KnownSymbol n => Sing n

instance KnownSymbol n => SingI (n :: Symbol) where
  sing = SSymbol

instance DecidableEquality Symbol where
  decideEquality SSymbol SSymbol = sameSymbol Proxy Proxy

{-------------------------------------------------------------------------------
  Singleton instance for lists
-------------------------------------------------------------------------------}

data instance Sing (xs :: [k]) where
  SNil  :: Sing '[]
  SCons :: Sing x -> Sing xs -> Sing (x ': xs)

instance                        SingI '[]       where sing = SNil
instance (SingI x, SingI xs) => SingI (x ': xs) where sing = SCons sing sing

{-------------------------------------------------------------------------------
  General purpose type level functions
-------------------------------------------------------------------------------}

type family Or (a :: Bool) (b :: Bool) where
  Or 'True b     = 'True
  Or a     'True = 'True
  Or _     _     = 'False

type family Equal (x :: k) (y :: k) where
  Equal x x = 'True
  Equal x y = 'False

type family Elem (x :: k) (xs :: [k]) where
  Elem x '[]       = 'False
  Elem x (y ': ys) = Or (Equal x y) (Elem x ys)

-- | Assert type-level predicate
--
-- We cannot define this in terms of a more general @If@ construct, because
-- @ghc@'s type-level language has an undefined reduction order and so we get
-- no short-circuiting.
type family Assert (b :: Bool) (err :: ErrorMessage) :: Constraint where
  Assert 'True  err = ()
  Assert 'False err = TypeError err

{-------------------------------------------------------------------------------
  Decidable equality gives a decidable membership check
-------------------------------------------------------------------------------}

data IsElem (x :: k) (xs :: [k]) where
  IsElem :: Elem x xs ~ 'True => IsElem x xs

shiftIsElem :: IsElem x ys -> IsElem x (y ': ys)
shiftIsElem IsElem = IsElem

checkIsElem ::
     DecidableEquality k
  => Sing (x :: k) -> Sing (xs :: [k]) -> Maybe (IsElem x xs)
checkIsElem _ SNil         = Nothing
checkIsElem x (SCons y ys) = case decideEquality x y of
                               Just Refl -> Just IsElem
                               Nothing   -> shiftIsElem <$> checkIsElem x ys

{-------------------------------------------------------------------------------
  Phantom type parameters
-------------------------------------------------------------------------------}

-- | Functors with phantom arguments
class Phantom (f :: k -> Type) where
  -- | Similar to 'Data.Functor.Contravariant.phantom', but without requiring
  -- 'Functor' or 'Contravariant'
  phantom :: forall a b. f a -> f b

data Poly (f :: k -> Type) = Poly (forall (a :: k). f a)

-- | Commute @Maybe@ and @forall@
--
-- NOTE: Technically speaking this is definable just in terms of 'Functor'
-- (see '_maybePolyFunctor'). However, that requires the _argument_ to be
-- polymorphic (rank-2 polymorphism); not a problem necessarily, but that then
-- eventually bubbles up and requires quantified constraints (due to a 'SingI'
-- contrained being required for @f a@ for all @a@), which are awkward to deal
-- with. The definition we provide here is easier to work with (we can pick
-- @a == Any@), and additionally avoids having to provide both 'Functor' and
-- 'Contrafunctor' instances; this definition simply is more direct.
maybePoly :: Phantom f => Maybe (f a) -> Maybe (Poly f)
maybePoly = fmap (\v -> Poly (phantom v))

-- | Variation on 'maybePoly'
--
-- Just here as documentation.
_maybePolyFunctor :: Functor f => (forall a. Maybe (f a)) -> Maybe (Poly f)
_maybePolyFunctor = fmap (\v -> Poly (fmap absurd v))