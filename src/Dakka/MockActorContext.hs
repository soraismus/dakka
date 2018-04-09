{-# LANGUAGE Trustworthy #-} -- Generalized newtype deriving for MockActorContext
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}
module Dakka.MockActorContext where

import "base" Data.Proxy ( Proxy )
import "base" Data.Typeable ( typeRep, TypeRep )
import "base" Data.Functor.Classes ( Show1(..) )

import "transformers" Control.Monad.Trans.State.Lazy ( StateT, execStateT )
import "transformers" Control.Monad.Trans.Writer.Lazy ( Writer, runWriter )

import "mtl" Control.Monad.Reader ( ReaderT, ask, MonadReader, runReaderT )
import "mtl" Control.Monad.State.Class ( MonadState( state ) )
import "mtl" Control.Monad.Writer.Class ( MonadWriter( tell ) )

import Dakka.Convert
import Dakka.Actor
import Dakka.Path
import Dakka.Constraints


-- | Encapsulates an interaction of a behavior with the context
data SystemMessage
    = forall a. Actor a => Create (Proxy a)
    | forall p. (Actor (Tip p), Actor (PRoot p)) => Send
        { to  :: ActorRef p
        , msg :: Message (Tip p) (PRoot p)
        }

instance Show SystemMessage where
    showsPrec d (Create p)      = showParen (d > 10) 
                                $ ("Create " ++)
                                . showsPrec 0 (typeRep p)
    showsPrec d (Send to' msg') = showParen (d > 10)
                                $ ("Send {to = " ++)
                                . showsPrec 11 to'
                                . (", msg = " ++)
                                . liftShowsPrec undefined undefined 11 msg'
                                . ("}" ++)

instance Eq SystemMessage where
    (Create a)   == (Create b)   = a =~= b
    (Send at am) == (Send bt bm) = demotePath at == demotePath bt && am =~~= bm
      where
        demotePath :: ActorRef p -> Path (Word, TypeRep)
        demotePath = convert
    _ == _ = False

-- | An ActorContext that simply collects all state transitions, sent messages and creation intents.
newtype MockActorContext p v = MockActorContext
    (ReaderT (ActorRef p) (StateT (Tip p) (Writer [SystemMessage])) v)
  deriving (Functor, Applicative, Monad, MonadWriter [SystemMessage], MonadReader (ActorRef p))

instance MonadState a (MockActorContext ('Root a)) where
    state = MockActorContext . state
instance MonadState a (MockActorContext (as ':/ a)) where
    state = MockActorContext . state

instance ActorContextConstraints p (MockActorContext p)
         => ActorContext p (MockActorContext p) where

    self = ask

    create' a = do
        tell [Create a]
        self <$/> a

    p ! m = tell [Send p m]

-- | Execute a 'Behavior' in a 'MockActorContext'.
execMock :: forall p b. ActorRef p -> MockActorContext p b -> Tip p -> (Tip p, [SystemMessage])
execMock ar (MockActorContext ctx) = runWriter . execStateT (runReaderT ctx ar)


execMock' :: forall p b. Actor (Tip p) => ActorRef p -> MockActorContext p b -> (Tip p, [SystemMessage])
execMock' ar ctx = execMock ar ctx startState

