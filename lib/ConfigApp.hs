{-# Language OverloadedStrings, ApplicativeDo #-}

module ConfigApp (
    jsMain
) where


import GHCJS.DOM (syncPoint, currentDocumentUnchecked)
import GHCJS.DOM.Types
import GHCJS.DOM.NonElementParentNode
import GHCJS.DOM.HTMLElement
import GHCJS.DOM.EventM (on)
import GHCJS.DOM.GlobalEventHandlers as E
import qualified GHCJS.DOM.HTMLTextAreaElement as TextArea

import qualified Data.Text as T
import Data.Semigroup
import qualified Data.List.NonEmpty as NE
import Data.Foldable

import Config
import Config.Schema


demoSpec :: ValueSpecs (Maybe [Rational], Maybe Bool, Maybe T.Text, [(Int,Int)])
demoSpec = sectionsSpec "top-level configuration" $
  do nums <- optSection' "numbers" (oneOrList valuesSpec)
             "Try out the number syntax"
     bool <- optSection' "yes-or-no" yesOrNoSpec
             "Using atoms as enumerations"
     str  <- optSection "string"
             "Strings use Haskell syntax"
     xs   <- reqSection' "coordinates" (oneOrList nestedMapSpec)
             "Example required section of a nested map"
     return (nums,bool,str,xs)

nestedMapSpec :: ValueSpecs (Int, Int)
nestedMapSpec = sectionsSpec "coord" $
  do x <- reqSection "x" "x coordinate"
     y <- reqSection "y" "y coordinate"
     return (x,y)

addDocumentation :: MonadJSM m => Document -> m ()
addDocumentation doc =
  do pre <- getThing doc HTMLPreElement "documentation"
     setInnerText pre (Just (show (generateDocs demoSpec)))

getThing :: (IsGObject a, MonadDOM m) => Document -> (JSVal -> a) -> String -> m a
getThing doc con eltId =
  do Just e <- getElementById doc eltId
     return $! uncheckedCastTo con e

jsMain :: JSM ()
jsMain = do
    doc <- currentDocumentUnchecked

    addDocumentation doc

    textarea <- getThing doc HTMLTextAreaElement "configinput"
    button   <- getThing doc HTMLButtonElement   "parse"
    output   <- getThing doc HTMLPreElement      "output"

    let selectError pos =
          do let i = posIndex pos
             TextArea.setSelectionRange textarea (Just i) (Just (i+1)) (Just ("forward" :: String))

    _ <- on button E.click $ do
        Just txt <- TextArea.getValue textarea
        case parse (txt <> "\n") of

          Left (ParseError pos e) ->
            do selectError pos
               setInnerText output $ Just $ unlines
                 [ "Parser error"
                 , showPosition pos ++ e ]

          Right x ->
            case loadValue demoSpec x of
              Left es ->
                do selectError (let LoadError p _ _ = NE.head es in p)
                   setInnerText output $ Just $ unlines
                     $ "Schema error"
                     : map showLoadError (toList es)

              Right y -> setInnerText output $ Just $ unlines
                           [ "Success" , show y ]

    syncPoint

showLoadError :: LoadError -> String
showLoadError (LoadError pos path problem) =
  showPosition pos ++
  T.unpack (T.concat (map (<>":") path)) ++
  " " ++
  showProblem problem

showPosition :: Position -> String
showPosition pos = show (posLine pos) ++ ":" ++ show (posColumn pos) ++ ": "

showProblem :: Problem -> String
showProblem (MissingSection x) = "missing required section `" ++ T.unpack x ++ "`"
showProblem (UnusedSection  x) = "unused section `"           ++ T.unpack x ++ "`"
showProblem (SpecMismatch   x) = "expected "                  ++ T.unpack x
