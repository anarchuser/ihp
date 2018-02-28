module Foundation.ControllerSupport (withContext, Action, renderHtml, renderPlain, param, paramInt, paramText, cs, (|>), redirectTo, renderNotFound, renderJson, params, ParamName (paramName), getRequestBody) where
    import ClassyPrelude
    import Foundation.HaskellSupport
    import Data.String.Conversions (cs)
    import Network.Wai (Response, Request, ResponseReceived, responseLBS, requestBody, queryString)
    import qualified Network.Wai
    import Network.HTTP.Types (status200, status302)
    import Foundation.ModelSupport
    import Foundation.ApplicationContext
    import Network.Wai.Parse as WaiParse
    import qualified Network.Wai.Util
    import qualified Data.ByteString.Lazy
    import qualified Network.URI
    import Data.Maybe (fromJust)
    import qualified Foundation.ViewSupport
    import qualified Data.Text.Read
    import qualified Data.Either
    import qualified Data.Text.Encoding
    import qualified Data.Text
    import qualified Data.Aeson

    import qualified Config

    import qualified Text.Blaze.Html.Renderer.Utf8 as Blaze
    import Text.Blaze.Html (Html)

    import Database.PostgreSQL.Simple as PG

    import Control.Monad.Reader

    data ControllerContext = ControllerContext Request Respond [WaiParse.Param] [WaiParse.File Data.ByteString.Lazy.ByteString]

    type Respond = Response -> IO ResponseReceived
    type WithControllerContext returnType = ReaderT ControllerContext IO returnType

    type Action = ((?controllerContext :: ControllerContext, ?modelContext :: ModelContext) => IO ResponseReceived)

    withContext :: Action -> ApplicationContext -> Request -> Respond -> IO ResponseReceived
    withContext theAction (ApplicationContext modelContext) request respond = do
        (params, files) <- WaiParse.parseRequestBodyEx WaiParse.defaultParseRequestBodyOptions WaiParse.lbsBackEnd request
        let
            ?controllerContext = ControllerContext request respond params files
            ?modelContext = modelContext
            in theAction

    --request :: StateT ControllerContext IO ResponseReceived -> Request
    --request = do
    --    ControllerContext request <- get
    --    return request

    --(|>) :: a -> f -> f a


    renderPlain :: (?controllerContext :: ControllerContext) => ByteString -> IO ResponseReceived
    renderPlain text = do
        let (ControllerContext _ respond _ _) = ?controllerContext
        respond $ responseLBS status200 [] (cs text)

    renderHtml :: (?controllerContext :: ControllerContext) => Foundation.ViewSupport.Html -> IO ResponseReceived
    renderHtml html = do
        let (ControllerContext request respond _ _) = ?controllerContext
        let boundHtml = let ?viewContext = Foundation.ViewSupport.ViewContext request in html
        respond $ responseLBS status200 [("Content-Type", "text/html")] (Blaze.renderHtml boundHtml)

    renderJson :: (?controllerContext :: ControllerContext) => Data.Aeson.ToJSON json => json -> IO ResponseReceived
    renderJson json = do
        let (ControllerContext request respond _ _) = ?controllerContext
        respond $ responseLBS status200 [("Content-Type", "application/json")] (Data.Aeson.encode json)

    renderNotFound :: (?controllerContext :: ControllerContext) => IO ResponseReceived
    renderNotFound = renderPlain "Not Found"

    redirectTo :: (?controllerContext :: ControllerContext) => Text -> IO ResponseReceived
    redirectTo url = do
        let (ControllerContext _ respond _ _) = ?controllerContext
        respond $ fromJust $ Network.Wai.Util.redirect status302 [] (fromJust $ Network.URI.parseURI (cs $ Config.baseUrl <> url))

    --params ::
    --params attributes = map readAttribute attributes

    param :: (?controllerContext :: ControllerContext) => ByteString -> ByteString
    param name = do
        let (ControllerContext request _ bodyParams _) = ?controllerContext
        let
            allParams :: [(ByteString, Maybe ByteString)]
            allParams = concat [(map (\(a, b) -> (a, Just b)) bodyParams), (queryString request)]
        fromMaybe (error $ "Required parameter " <> cs name <> " is missing") (join (lookup name allParams))

    paramInt :: (?controllerContext :: ControllerContext) => ByteString -> Int
    paramInt name = fst $ Data.Either.fromRight (error $ "Invalid parameter " <> cs name) (Data.Text.Read.decimal $ cs $ param name)

    paramText :: (?controllerContext :: ControllerContext) => ByteString -> Text
    paramText name = cs $ param name

    getRequestBody :: (?controllerContext :: ControllerContext) => IO ByteString
    getRequestBody =
        let (ControllerContext request _ _ _ ) = ?controllerContext
        in Network.Wai.requestBody request

    class ParamName a where
        paramName :: a -> ByteString

    instance ParamName ByteString where
        paramName = ClassyPrelude.id

    params :: (?controllerContext :: ControllerContext) => ParamName a => [a] -> [(a, ByteString)]
    params = map (\name -> (name, param $ paramName name))