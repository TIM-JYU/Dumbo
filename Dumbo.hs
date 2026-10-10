-- ============================================================================
-- Dumbo.hs
--
-- Purpose:
-- Provide the TIM Markdown conversion service.
--
-- Dumbo uses Pandoc to read Markdown and convert it to HTML or LaTeX.
-- It also supports conversion of JSON input containing Markdown fields.
--
-- Mathematical expressions can be rendered using:
--   - SVG:    SVG graphics embedded as Base64 data URLs.
--   - CSVG:   SVG graphics embedded directly in HTML.
--   - MathJAX: expressions left for MathJax to render in the browser.
--
-- The service exposes HTTP endpoints for Markdown and LaTeX conversion,
-- including endpoints for processing JSON fields with conversion keys.
--
-- Cache:
-- Generated mathematical output is cached on disk to avoid repeating
-- expensive LaTeX and SVG conversions.
--
-- The cache root directory is supplied through the cacheDir argument.
-- Cache keys are generated in Tex2Svg.hs. The current cache layout uses
-- two hexadecimal characters as the first directory name and the remaining
-- characters as the cache filename.
--
-- The service can also read entries from the legacy cache layout.
-- New entries are written using the current layout.
-- ============================================================================

{-#OPTIONS_GHC -Wall #-}
{-#LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-#LANGUAGE DataKinds #-}
{-#LANGUAGE FlexibleInstances #-}
{-#LANGUAGE TypeOperators #-}
{-#LANGUAGE DeriveGeneric #-}
{-#LANGUAGE DeriveFunctor #-}
{-#LANGUAGE DeriveFoldable #-}
{-#LANGUAGE DeriveTraversable #-}
module Main where
import Text.Pandoc.Walk
import qualified Text.Pandoc as PDC
import qualified Text.Pandoc.Options as PDC_Opt
import GHC.Generics
import System.Directory
import qualified Data.Vector as V
import Control.Monad.Trans
import Control.Monad
import Data.Maybe
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.Lazy as LT
import Control.Lens (transformM)
import qualified Data.ByteString.Lazy as LBS
import System.FilePath
import Snap.Core hiding (pass)
import Data.Aeson
import Data.Aeson.Types
import Data.Aeson.Lens()
import Snap.Http.Server
import Text.Blaze.Html.Renderer.Text
import Control.Applicative
import qualified AsciiMath
import Tex2Svg
import Options.Generic
import Text.LaTeX.Base.Syntax
import Text.LaTeX.Base.Parser
import qualified Data.Set as Set
import Numeric (showHex)

defaultReader :: PDC.Reader PDC.PandocIO
defaultReader = PDC.TextReader PDC.readMarkdown

tex2SvgPass :: DumboRTC -> T.Text -> (PDC.Block -> IO PDC.Block)
tex2SvgPass drtc preamble = walkM (tex2svg (tex2svgRtc drtc) preamble . rawInlinePass) . rawBlockPass

tex2CSvgPass :: DumboRTC -> T.Text -> (PDC.Block -> IO PDC.Block)
tex2CSvgPass drtc preamble =
  walkM (tex2csvg (tex2svgRtc drtc) preamble . rawInlinePass) .
  rawBlockPass

latexMathPass :: (T.Text -> a) -> T.Text -> a -> a
latexMathPass d s b =
  case parseLaTeX s of
   Left _ -> b
   Right tex -> maybeMath tex
    where maybeMath t | isMath t = d s
          maybeMath _t = b

rawInlinePass :: PDC.Inline -> PDC.Inline
rawInlinePass b@(PDC.RawInline "tex" s) = latexMathPass (PDC.Math PDC.DisplayMath) s b
rawInlinePass b = b

rawBlockPass :: PDC.Block -> PDC.Block
rawBlockPass b@(PDC.RawBlock "tex" tex) = latexMathPass (\s -> PDC.Plain [PDC.Math PDC.DisplayMath s]) tex b
rawBlockPass b = b

isMath :: LaTeX -> Bool
isMath (TeXEnv name _ _) = Set.member name mathEnvsSet
isMath (TeXSeq l1 l2) = isMath l1 || isMath l2
isMath _ = False

convertBlock :: PDC.Reader PDC.PandocIO -> PDC.ReaderOptions -> OutputFormat -> (PDC.Block -> IO PDC.Block) -> T.Text -> IO LT.Text
convertBlock reader rOpts target ms txt = do
    pdc <- PDC.runIO $  
        case reader of
            PDC.TextReader parseIt -> (parseIt rOpts txt) >>= make
            PDC.ByteStringReader parseIt -> (parseIt rOpts (LBS.fromStrict (T.encodeUtf8 txt))) >>= make
    pure (either (LT.pack . show) id pdc)
 where
  make :: (PDC.PandocMonad m, MonadIO m) => PDC.Pandoc -> m LT.Text
  make x = case target of
        ToHTML  -> do
          r <- walkM (liftIO . ms) x
          makeHtml r
        ToLatex -> makeLatex x
  makeHtml, makeLatex :: PDC.PandocMonad m => PDC.Pandoc -> m LT.Text
  makeHtml  pdc  = fmap renderHtml (PDC.writeHtml5 htmlOpts pdc)
  makeLatex pdc =  LT.fromStrict <$> PDC.writeLaTeX latexOpts pdc

readerOpts :: TIMIFace a -> ConversionElement Text -> PDC.Extensions -> PDC_Opt.ReaderOptions
readerOpts timInput ce exts =
  PDC.def
  { PDC.readerExtensions
     =  PDC_Opt.enableExtension PDC_Opt.Ext_tex_math_dollars
        . smartPunctExt
        $ exts
  }
  where
    curSmartPunct = case ce of
        CEBare _ -> defSmartPunct ?: smartPunct timInput
        CEWrapped obj -> defSmartPunct ?: smartPunct obj
    -- Smart punct is enabled by default in readers that properly support it.
    smartPunctExt = if curSmartPunct then id else PDC_Opt.disableExtension PDC_Opt.Ext_smart


latexOpts :: PDC_Opt.WriterOptions
latexOpts = PDC.def

htmlOpts :: PDC_Opt.WriterOptions
htmlOpts =
  PDC.def
  { PDC.writerHTMLMathMethod =
    PDC.MathJax
      "https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.1/MathJax.js?config=TeX-AMS-MML_HTMLorMML"
  , PDC.writerExtensions = PDC_Opt.enableExtension PDC_Opt.Ext_definition_lists
                           . PDC_Opt.enableExtension PDC_Opt.Ext_latex_macros
                           $ PDC.pandocExtensions
  }

stripSome :: (T.Text -> T.Text -> Maybe T.Text) -> T.Text -> T.Text -> T.Text
stripSome f piece str = fromMaybe str (f piece str)

stripP :: T.Text -> T.Text
stripP = stripSome T.stripSuffix "</p>" . stripSome T.stripPrefix "<p>"

data OutputFormat = ToHTML | ToLatex deriving (Eq,Show)

data DumboArgs f = DC {latex     :: f ::: Maybe FilePath <?> "Absolute path to latex binary"
                      ,dvisvgm   :: f ::: Maybe FilePath <?> "Absolute path to dvisvgm binary"
                      ,cacheDir  :: f ::: FilePath <?> "Directory for cached math"
                      ,tmpDir    :: f ::: FilePath <?> "Directory to store temporary files"
                      ,port      :: f ::: Int <?> "Service port number" }
                    deriving (Generic)

instance ParseRecord (DumboArgs Wrapped)

data DumboRTC = DRTC {
                     tex2svgRtc :: Tex2SvgRuntime
                     ,portN :: Int
                     }

(?:) :: a -> Maybe a -> a
a ?: b = fromMaybe a b

initialize :: DumboArgs Unwrapped -> IO DumboRTC
initialize dargs = do
  latexP   <- maybe findLatex mkLatex (Main.latex dargs)
  dvisvgmP <- maybe findDVISVGM mkDVISVGM (Main.dvisvgm dargs)
  -- Cache path handling.
  --
  -- Current layout:
  --   <cacheDir>/<first 2 hex characters>/<remaining hex characters>.cache
  --
  -- Legacy layout:
  --   <cacheDir>/<key grouped into 3-character directory names>.cache
  --
  -- Reads try the current layout first and then the legacy layout.
  -- Writes use only the current layout and create missing directories.  
  let cacheFN :: Integer -> FilePath
      cacheFN i =
        let hex = showHex i ""
            padded = replicate (40 - length hex) '0' ++ hex
        in cacheDir dargs ++ "/" ++ take 2 padded ++ "/" ++ drop 2 padded ++ ".cache"

      oldCacheFN :: Integer -> FilePath
      oldCacheFN i = cacheDir dargs ++ "/" ++ triep (show i)

      triep :: String -> FilePath
      triep [a,b,c] = a:b:c:".cache"
      triep (a:b:c:xs) = a:b:c:'/':triep xs
      triep xs = xs

      readCacheFile :: FilePath -> IO (Maybe PDC.Inline)
      readCacheFile path = do
        e <- doesFileExist path
        if e then decode <$> LBS.readFile path else pure Nothing

      cacheRead :: Integer -> IO (Maybe PDC.Inline)
      cacheRead i = do
        newCache <- readCacheFile (cacheFN i)
        case newCache of
          Just result -> pure (Just result)
          Nothing -> readCacheFile (oldCacheFN i)

      cacheWrite :: Integer -> PDC.Inline -> IO ()
      cacheWrite i inline = do
        let path = cacheFN i
        createDirectoryIfMissing True (takeDirectory path)
        LBS.writeFile path (encode inline)
  return $ DRTC (T2SR
                cacheRead
                cacheWrite
                (tmpDir dargs)
                latexP
                dvisvgmP)
                (port dargs)

main :: IO ()
main = do
  args <- unwrapRecord "Dumboest markdown converter"
  rtc  <- initialize args
  httpServe (setPort (portN rtc) mempty)
    $   route
          [ ("mdkeys"    , method POST (transformKeys rtc ToHTML))
          , ("markdown"  , method POST (transformMD   rtc ToHTML))
          , ("latexkeys" , method POST (transformKeys rtc ToLatex))
          , ("latex"     , method POST (transformMD   rtc ToLatex))
          ]
    <|> ifTop (method POST (transformMD rtc ToHTML))

transformKeys :: MonadSnap m0 => DumboRTC -> OutputFormat -> m0 ()
transformKeys rtc target = conversion (keysConvert rtc target)

transformMD :: MonadSnap m0 => DumboRTC -> OutputFormat -> m0 ()
transformMD rtc target   = conversion (plainConvert rtc target)

keysConvert :: DumboRTC -> OutputFormat -> TIMIFace a -> ConversionElement Value -> IO Value
keysConvert rtc target timInput
 = (\(pass,obj) -> transformM (jsonEditing timInput target pass) obj) . convertElement rtc (mathOption timInput) (mathPreamble timInput)

plainConvert :: DumboRTC -> OutputFormat -> TIMIFace el -> ConversionElement Text -> IO LT.Text
plainConvert rtc target timInput cel
 = do
    let converted = convertElement rtc (mathOption timInput) (mathPreamble timInput) cel
    result <- PDC.runIO (PDC.getReader (getInputFormat timInput cel))
    (currentReader, extss) <- PDC.handleError result
    let opts = readerOpts timInput cel extss
    uncurry (convertBlock currentReader opts target) converted

modifyJSON :: TIMIFace a -> OutputFormat -> (PDC.Block -> IO PDC.Block) -> Text -> IO Value
modifyJSON timInput target pass str = String . stripP . LT.toStrict <$> convertBlock defaultReader (readerOpts timInput (CEBare str) PDC_Opt.pandocExtensions) target pass str

jsonEditing :: TIMIFace a -> OutputFormat -> (PDC.Block -> IO PDC.Block) -> Value -> IO Value
jsonEditing timInput target pass (String str)
  | "md:" `T.isPrefixOf` str
    -- ^ Convert field from markdown to target
  = modifyJSON timInput target pass (T.drop 3 str)
  | "am:" `T.isPrefixOf` str
  = modifyJSON timInput target (pass <=< walkM convertAsciiMath) (T.drop 3 str)
    -- ^ Convert field from md to target, but assume that math is asciiMath
jsonEditing _ _ _ x = pure x

convertAsciiMath (PDC.Math a s) =
  pure $ either (const (PDC.Math a s)) (PDC.Math a) (fmap T.pack $ AsciiMath.compile $ T.unpack s)
convertAsciiMath x = pure x

mkErr :: String -> String -> Value
mkErr s e = object ["error" .= e, "stage" .= s]

getInputFormat timInput ce
  = case ce of
      CEBare txt -> defInputFormat ?: inputFormat timInput
      CEWrapped obj -> defInputFormat ?: inputFormat timInput ?: inputFormat obj

convertElement rtc globalMath globalPreamble ce
  = case ce of
      CEBare txt ->
        case defMathOption ?: globalMath of
          SVG ->
            (tex2SvgPass rtc (defPreamble ?: globalPreamble), txt)

          CSVG ->
            (tex2CSvgPass rtc (defPreamble ?: globalPreamble), txt)

          MathJAX ->
            (pure, txt)

      CEWrapped obj ->
        case defMathOption ?: globalMath ?: mathOption obj of
          SVG ->
            (tex2SvgPass rtc
              (defPreamble ?: globalPreamble ?: mathPreamble obj),
             content obj)

          CSVG ->
            (tex2CSvgPass rtc
              (defPreamble ?: globalPreamble ?: mathPreamble obj),
             content obj)

          MathJAX ->
            (pure, content obj)

conversion :: (MonadIO m0, ToJSON b0,FromJSON a0,MonadSnap m0) =>
                (TIMIFace (V.Vector a0) -> a0 -> IO b0) -> m0 ()
conversion f = do
  bdy <- eitherDecode `fmap` readRequestBody 1000000000 -- Allow up to gigabyte at once..
  case bdy of
    Left  err      -> writeLBS . encode $ mkErr "Decoding input" err
    Right timInput -> liftIO (V.mapM (f timInput) (content timInput)) >>= writeLBS . encode

data MathOption = SVG | CSVG | MathJAX deriving (Eq,Show)

defMathOption :: MathOption
defMathOption = MathJAX

defPreamble :: T.Text
defPreamble = ""

defInputFormat :: T.Text
defInputFormat = "markdown"

defSmartPunct :: Bool
defSmartPunct = False

instance FromJSON MathOption where
    parseJSON (String txt) = case txt of
        "svg"     -> pure SVG
        "csvg"    -> pure CSVG
        "mathjax" -> pure MathJAX
        _         -> fail ("Unexpected math option" ++ show txt)
    parseJSON invalid = typeMismatch "MathOption" invalid

data ConversionElement el =
                         CEBare el
                       | CEWrapped (TIMIFace el)
                       deriving (Eq,Show)

instance FromJSON el => FromJSON (ConversionElement el) where
    parseJSON o = (CEWrapped <$> parseJSON o) <|> (CEBare <$> parseJSON o)
    parseJSON invalid    = typeMismatch "ConversionElement" invalid

data TIMIFace el = TIF {content      :: el
                       ,inputFormat  :: Maybe T.Text
                       ,mathOption   :: Maybe MathOption
                       ,mathPreamble :: Maybe T.Text
                       ,smartPunct   :: Maybe Bool}
                       deriving (Eq,Show,Functor,Foldable,Traversable)

instance FromJSON el => FromJSON (TIMIFace el) where
    parseJSON (Object v) = do
      content     <- v .: "content"
      inputFormat <- optional (v .: "inputFormat")
      mathOpt     <- optional (v .: "mathOption")
      mathPre     <- optional (v .: "mathPreamble")
      smartPunct  <- optional (v .: "smartPunct")
      return (TIF content inputFormat mathOpt mathPre smartPunct)

    parseJSON invalid    = typeMismatch "TIMIFace" invalid
