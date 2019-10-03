{-# LANGUAGE ApplicativeDo        #-}
{-# LANGUAGE DeriveGeneric        #-}
{-# LANGUAGE DerivingVia          #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE QuasiQuotes          #-}
{-# LANGUAGE RecordWildCards      #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE UndecidableInstances #-}
module Fly.Types where

import Control.Monad.Trans.State.Strict
import Data.Aeson                       hiding (Result)
import Data.Aeson.Casing
import Data.Aeson.TH
import Data.HashMap.Strict
import Data.Maybe                       (fromMaybe)
import Data.Scientific                  (fromFloatDigits)
import Dhall
import Dhall.Core
import Dhall.Src
import Dhall.TH
import Dhall.TypeCheck                  (X)
import GHC.Generics

import qualified Data.Foldable       as F
import qualified Data.HashMap.Strict as M
import qualified Data.Text           as T
import qualified Data.Vector         as V
import qualified Dhall.Map

data CustomResourceType = CustomResourceType { crtName   :: Text
                                             , crtType   :: Text
                                             , crtSource :: Maybe (HashMap Text Value)
                                             , crtPrivileged :: Maybe Bool
                                             , crtParams :: Maybe (HashMap Text Value)
                                             , crtCheckEvery :: Maybe Text
                                             , crtTags :: Maybe Text
                                             , crtUniqueVersionHistory :: Maybe Bool
                                             }
                    deriving (Show, Generic, Eq)
                    deriving Interpret via InterpretWithPrefix CustomResourceType

data ResourceType = ResourceTypeInBuilt Text
                  | ResourceTypeCustom CustomResourceType
                    deriving (Show, Generic, Eq)

instance Interpret ResourceType where
  autoWith _ = Dhall.union ( ( ResourceTypeInBuilt <$> constructor "InBuilt" strictText)
                           <> ( ResourceTypeCustom <$> constructor "Custom" auto ))

data Resource = Resource { resourceName         :: Text
                         , resourceType         :: ResourceType
                         , resourceIcon         :: Maybe Text
                         , resourcePublic       :: Maybe Bool
                         , resourceSource       :: Maybe (HashMap Text Value)
                         , resourceVersion      :: Maybe (HashMap Text Text)
                         , resourceCheckEvery   :: Maybe Text
                         , resourceTags         :: Maybe [Text]
                         , resourceWebhookToken :: Maybe Text}
              deriving (Show, Generic, Eq)
              deriving Interpret via InterpretWithPrefix Resource

instance ToJSON Resource where
  toJSON x = case genericToJSON (aesonPrefix snakeCase) x of
               Object m -> Object $ M.insert "type" (resourceTypeValue $ resourceType x) m
               v -> error ("Expected " ++ show v ++ "to be Object")
             where
               resourceTypeValue (ResourceTypeInBuilt t) = String t
               resourceTypeValue (ResourceTypeCustom t)  = String $ crtName t

data TaskRunConfig = TaskRunConfig { trcPath :: Text
                                   , trcArgs :: Maybe [Text]
                                   , trcDir  :: Maybe Text
                                   , trcUser :: Maybe Text
                                   }
                   deriving (Show, Generic, Eq)
                   deriving Interpret via InterpretWithPrefix TaskRunConfig

data TaskImageResource = TaskImageResource { tirType    :: Text
                                           , tirSource  :: Maybe (HashMap Text Value)
                                           , tirParams  :: Maybe (HashMap Text Value)
                                           , tirVersion :: Maybe (HashMap Text Text)
                                           }
                       deriving (Show, Generic, Eq)
                       deriving Interpret via InterpretWithPrefix TaskImageResource

data TaskInput = TaskInput { tiName     :: Text
                           , tiPath     :: Maybe Text
                           , tiOptional :: Maybe Bool
                           }
               deriving (Show, Generic, Eq)
               deriving Interpret via InterpretWithPrefix TaskInput

data TaskOutput = TaskOutput { toName :: Text, toPath :: Maybe Text }
                deriving (Show, Generic, Eq)
                deriving Interpret via InterpretWithPrefix TaskOutput

data TaskCache = TaskCache { taskcachePath :: Text}
               deriving (Show, Generic, Eq)
               deriving Interpret via InterpretWithPrefix TaskCache

data TaskContainerLimits = TaskContainerLimits { tclCpu    :: Maybe Natural
                                               , tclMemory :: Maybe Natural}
                         deriving (Show, Generic, Eq)
                         deriving Interpret via InterpretWithPrefix TaskContainerLimits

data TaskConfig = TaskConfig { tcPlatform        :: Text
                             , tcRun             :: TaskRunConfig
                             , tcImageResource   :: Maybe TaskImageResource
                             , tcRootfsUri       :: Maybe Text
                             , tcInputs          :: Maybe [TaskInput]
                             , tcOutputs         :: Maybe [TaskOutput]
                             , tcCaches          :: Maybe [TaskCache]
                             , tcParams          :: Maybe (HashMap Text (Maybe Text))
                             , tcContainerLimits :: Maybe TaskContainerLimits
                             }
                deriving (Show, Generic, Eq)
                deriving Interpret via InterpretWithPrefix TaskConfig

data TaskSpec = TaskSpecFile Text | TaskSpecConfig TaskConfig
              deriving (Show, Generic, Eq)

instance Interpret TaskSpec where
  autoWith _ = Dhall.union ((TaskSpecFile <$> constructor "File" strictText)
                           <> (TaskSpecConfig <$> constructor "Config" auto))

instance ToJSON TaskSpec where
  toJSON (TaskSpecFile f)   = object [ "file" .= f ]
  toJSON (TaskSpecConfig c) = object [ "config" .= c ]

data GetVersion = GetVersionLatest
                | GetVersionEvery
                | GetVersionSpecific (HashMap Text Text)
                deriving (Show, Generic, Eq)

instance ToJSON GetVersion where
  toJSON GetVersionLatest       = String "latest"
  toJSON GetVersionEvery        = String "every"
  toJSON (GetVersionSpecific v) = toJSON v

instance Interpret GetVersion where
  autoWith _ = Dhall.union ((GetVersionLatest <$ constructor "Latest" strictText)
                           <> (GetVersionEvery <$ constructor "Every" strictText)
                           <> (GetVersionSpecific <$> constructor "SpecificVersion" auto))

data GetStep = GetStep { getGet      :: Maybe Text
                       , getResource :: Resource
                       , getParams   :: Maybe (HashMap Text Value)
                       , getVersion  :: Maybe GetVersion
                       , getPassed   :: Maybe [Text]
                       , getTrigger  :: Maybe Bool
                       , getTags     :: Maybe [Text]
                       , getTimeout  :: Maybe Text
                       , getAttempts :: Maybe Natural
                       }
             deriving (Show, Generic, Eq)
             deriving Interpret via InterpretWithPrefix GetStep

instance ToJSON GetStep where
  toJSON GetStep{..} = object [ "get"      .= fromMaybe (resourceName getResource) getGet
                              , "resource" .= toJSON ((resourceName getResource) <$ getGet)
                              , "params"   .= getParams
                              , "version"  .= getVersion
                              , "passed"   .= getPassed
                              , "trigger"  .= getTrigger
                              , "tags"     .= getTags
                              , "timeout"  .= getTimeout
                              , "attempts" .= getAttempts
                              ]

data PutStep = PutStep { putPut       :: Maybe Text
                       , putResource  :: Resource
                       , putParams    :: Maybe (HashMap Text Value)
                       , putGetParams :: Maybe (HashMap Text Value)
                       , putTags      :: Maybe [Text]
                       , putTimeout   :: Maybe Text
                       , putAttempts  :: Maybe Natural
                       }
             deriving (Show, Generic, Eq)
             deriving Interpret via InterpretWithPrefix PutStep

instance ToJSON PutStep where
  toJSON PutStep{..} = object [ "put"        .= fromMaybe (resourceName putResource) putPut
                              , "resource"   .= toJSON ((resourceName putResource) <$ putPut)
                              , "params"     .= putParams
                              , "get_params" .= putGetParams
                              ]

data TaskStep = TaskStep { taskTask          :: Text
                         , taskConfig        :: TaskSpec
                         , taskPrivileged    :: Maybe Bool
                         , taskParams        :: Maybe (HashMap Text Text)
                         , taskImage         :: Maybe Text
                         , taskInputMapping  :: Maybe (HashMap Text Text)
                         , taskOutputMapping :: Maybe (HashMap Text Text)
                         }
              deriving (Show, Generic, Eq)
              deriving Interpret via InterpretWithPrefix TaskStep

instance ToJSON TaskStep where
  toJSON t@(TaskStep{..}) = case genericToJSON (aesonPrefix snakeCase) t of
                          Object o1 -> case toJSON taskConfig of
                                         Object o2 ->
                                           Object ( (M.delete "config" o1) `M.union` o2)
                                         v -> error ("Expected " ++ show v ++ "to be Object")
                          v -> error ("Expected " ++ show v ++ "to be Object")

data Step = Get { stepGet :: GetStep, stepHooks :: StepHooks }
          | Put { stepPut :: PutStep, stepHooks :: StepHooks }
          | Task { stepTask :: TaskStep, stepHooks :: StepHooks }
          | Aggregate { aggregatedSteps :: [Step], stepHooks :: StepHooks }
          | Do { doSteps :: [Step], stepHooks :: StepHooks  }
          | Try { tryStep :: Step, stepHooks :: StepHooks  }
          deriving (Show, Generic, Eq)

instance Interpret Step where
  autoWith _ = Dhall.Type{..} where
    expected = [dhallExpr|./dhall-concourse/types/Step.dhall|]
    extract (Lam _ _ -- Step
             (Lam _ _ -- GetStep
              (Lam _ _ -- PutStep
               (Lam _ _ -- TaskStep
                (Lam _ _ -- AggregateStep
                 (Lam _ _ -- DoStep
                  (Lam _ _ -- TryStep
                   x))))))) = extractStepFromApps x
    extract x = extractStepFromApps x -- While recursing it loses all the `Lam`s
    extractStepFromApps (App (App (Var (V _ 5)) s) hooks) = buildStep Get s hooks
    extractStepFromApps (App (App (Var (V _ 4)) s) hooks) = buildStep Put s hooks
    extractStepFromApps (App (App (Var (V _ 3)) s) hooks) = buildStep Task s hooks
    extractStepFromApps (App (App (Var (V _ 2)) s) hooks) = buildStep Aggregate s hooks
    extractStepFromApps (App (App (Var (V _ 1)) s) hooks) = buildStep Do s hooks
    extractStepFromApps (App (App (Var (V _ 0)) s) hooks) = buildStep Try s hooks
    extractStepFromApps t = typeError expected t
    buildStep f x y = f <$> Dhall.extract auto x <*> Dhall.extract auto y

mergeHooks :: ToJSON a => a -> StepHooks -> Value
mergeHooks step hooks = case toJSON step of
                          Object o1 -> case toJSON hooks of
                                         Object o2 -> Object (o1 `M.union` o2)
                                         v -> error ("Expected " ++ show v ++ "to be Object")
                          v -> error ("Expected " ++ show v ++ "to be Object")

instance ToJSON Step where
  toJSON (Get g h)           = mergeHooks g h
  toJSON (Put p h)           = mergeHooks p h
  toJSON (Task t h)          = mergeHooks t h
  toJSON (Aggregate steps h) = mergeHooks (object ["aggregate" .= steps]) h
  toJSON (Do steps h)        = mergeHooks (object ["do" .= steps]) h
  toJSON (Try step h)        = mergeHooks (object ["try" .= step]) h

data StepHooks = StepHooks { hookOnSuccess :: Maybe Step
                           , hookOnFailure :: Maybe Step
                           , hookOnAbort   :: Maybe Step
                           , hookEnsure    :: Maybe Step
                           }
               deriving (Show, Generic, Eq)
               deriving Interpret via InterpretWithPrefix StepHooks

data JobBuildLogRetention = JobBuildLogRetention { jblrDays   :: Maybe Natural
                                                 , jblrBuilds :: Maybe Natural
                                                 }
                          deriving (Show, Generic, Eq)
                          deriving Interpret via InterpretWithPrefix JobBuildLogRetention

data Job = Job { jobName                 :: Text
               , jobOldName              :: Maybe Text
               , jobPlan                 :: [Step]
               , jobSerial               :: Maybe Bool
               , jobBuildLogRetention    :: Maybe JobBuildLogRetention
               , jobBuildLogsToRetain    :: Maybe Natural
               , jobSerialGroups         :: Maybe [Text]
               , jobMaxInFlight          :: Maybe Natural
               , jobPublic               :: Maybe Bool
               , jobDisableManualTrigger :: Maybe Bool
               , jobInterruptible        :: Maybe Bool
               , jobOnSuccess            :: Maybe Step
               , jobOnFailure            :: Maybe Step
               , jobOnAbort              :: Maybe Step
               , jobEnsure               :: Maybe Step
               }
         deriving (Show, Generic, Eq)
         deriving Interpret via InterpretWithPrefix Job

newtype InterpretWithPrefix a = InterpretWithPrefix a

instance (Generic a, GenericInterpret (Rep a)) => Interpret (InterpretWithPrefix a) where
  autoWith opts =
    let modifier = T.pack . (fieldLabelModifier $ aesonPrefix snakeCase) . T.unpack
    in InterpretWithPrefix <$> fmap GHC.Generics.to (evalState (genericAutoWith opts{fieldModifier = modifier}) 1)

withType :: Dhall.Map.Map Text (Expr Src X) -> Text -> Type a -> Dhall.Extractor Src X a
withType m key t = case Dhall.Map.lookup key m of
                     Nothing -> extractError $ "expected to find key: "  <> key
                     Just x -> Dhall.extract t x

instance Interpret Value where
  autoWith _ = Dhall.Type{..} where
    expected = [dhallExpr|./dhall-concourse/lib/prelude-json.dhall|]
    extract (Lam _ (Const Dhall.Core.Type)
              (Lam _ _ x)) = extractJSONFromApps x
    extract x = extractJSONFromApps x
    extractJSONFromApps (App (Field (Var (V _ 0)) "bool") (BoolLit b)) = pure $ Data.Aeson.Bool b
    extractJSONFromApps (App (Field (Var (V _ 0)) "string") (TextLit (Chunks _ t))) = pure $ String t
    extractJSONFromApps (App (Field (Var (V _ 0)) "number") (DoubleLit n)) = pure $ Number $ fromFloatDigits n
    extractJSONFromApps (App (Field (Var (V _ 0)) "object") o) = Object <$> Dhall.extract auto o
    extractJSONFromApps (App (Field (Var (V _ 0)) "array") a) = Array . V.fromList <$> Dhall.extract auto a
    extractJSONFromApps (Field (Var (V _ 0)) "null") = pure Null
    extractJSONFromApps t = typeError expected t

instance Interpret (HashMap Text Value) where
  autoWith _ = Dhall.Type{..} where
    expected = [dhallExpr|./dhall-concourse/types/JSONObject.dhall|]
    extract (ListLit _ x) =
      M.fromList <$> (Prelude.sequenceA $ F.toList $ fmap extractPair x)
    extract t = typeError expected t
    extractPair (RecordLit m) = do
      key <- withType m "mapKey" auto
      val <- withType m "mapValue" auto
      pure (key, val)
    extractPair _ = extractError "expected record"

instance Interpret (HashMap Text Text) where
  autoWith _ = Dhall.Type{..} where
    expected = [dhallExpr|List ./dhall-concourse/types/TextTextPair.dhall|]
    extract (ListLit _ x) =
      M.fromList <$> (Prelude.sequenceA $ F.toList $ fmap extractPair x)
    extract t = typeError expected t
    extractPair (RecordLit m) = do
      key <- withType m "mapKey" auto
      val <- withType m "mapValue" auto
      pure (key, val)
    extractPair _ = extractError "expected record"

instance Interpret (HashMap Text (Maybe Text)) where
  autoWith _ = Dhall.Type{..} where
    expected = [dhallExpr|List { mapKey : Text, mapValue : Optional Text }|]
    extract (ListLit _ x) =
      M.fromList <$> (Prelude.sequenceA $ F.toList $ fmap extractPair x)
    extract t = typeError expected t
    extractPair (RecordLit m) = do
      key <- withType m "mapKey" auto
      val <- withType m "mapValue" auto
      pure (key, val)
    extractPair _ = extractError "expected record"

instance {-# OVERLAPPING #-} ToJSON (HashMap Text Text) where
  toJSON xs = object (toPairs $ M.toList xs)
              where toPairs []                = []
                    toPairs ((key, value):xs) = (key .= value) : toPairs xs

instance {-# OVERLAPPING #-} ToJSON (HashMap Text (Maybe Text)) where
  toJSON xs = object (toPairs $ M.toList xs)
              where toPairs []                = []
                    toPairs ((key, value):xs) = (key .= value) : toPairs xs

$(deriveToJSON (aesonPrefix snakeCase) ''CustomResourceType)
$(deriveToJSON (aesonPrefix snakeCase){sumEncoding = UntaggedValue} ''ResourceType)
$(deriveToJSON (aesonPrefix snakeCase) ''TaskRunConfig)
$(deriveToJSON (aesonPrefix snakeCase) ''TaskImageResource)
$(deriveToJSON (aesonPrefix snakeCase) ''TaskInput)
$(deriveToJSON (aesonPrefix snakeCase) ''TaskOutput)
$(deriveToJSON (aesonPrefix snakeCase) ''TaskCache)
$(deriveToJSON (aesonPrefix snakeCase) ''TaskConfig)
$(deriveToJSON (aesonPrefix snakeCase) ''TaskContainerLimits)
$(deriveToJSON (aesonPrefix snakeCase) ''StepHooks)
$(deriveToJSON (aesonPrefix snakeCase) ''JobBuildLogRetention)
$(deriveToJSON (aesonPrefix snakeCase) ''Job)
