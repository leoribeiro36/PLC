import qualified Language.ECMAScript3.Parser as Parser
import Language.ECMAScript3.Syntax
import Control.Monad hiding (empty)
import Control.Applicative hiding (empty)
import Data.Map as Map
import Debug.Trace
import Value

--
-- Evaluate functions
--

evalExpr :: StateT -> Expression -> StateTransformer Value
evalExpr env (VarRef (Id id)) = stateLookup env id
evalExpr env (IntLit int) = return $ Int int
evalExpr env (InfixExpr op expr1 expr2) = do
    v1 <- evalExpr env expr1
    v2 <- evalExpr env expr2
    infixOp env op v1 v2
evalExpr env (AssignExpr OpAssign (LVar var) expr) = do
    v <- stateLookup env var
    case v of
        -- Variable not defined :(
        (Error _) -> return $ Error $ (show var) ++ " not defined"
        -- Variable defined, let's set its value
        _ -> do
            e <- evalExpr env expr
            setVar var e
			
evalForInit :: StateT -> ForInit -> StateTransformer Value
evalForInit env (NoInit) = return Nil
evalForInit env (VarInit []) = return Nil 
evalForInit env (VarInit (decl:ds)) = varDecl env decl >> evalForInit env (VarInit ds)
evalForInit env (ExprInit expr) = evalExpr env expr

evalStmt :: StateT -> Statement -> StateTransformer Value
evalStmt env EmptyStmt = return Nil
evalStmt env (VarDeclStmt []) = return Nil
evalStmt env (VarDeclStmt (decl:ds)) =
    varDecl env decl >> evalStmt env (VarDeclStmt ds)
evalStmt env (ExprStmt expr) = evalExpr env expr
evalStmt env (IfStmt expr estado1 estado2) = evalIfElse env expr estado1 estado2
evalStmt env (IfSingleStmt expr estado) = evalIf env expr estado
evalStmt env (BlockStmt []) = return Nil
evalStmt env (BlockStmt ((BreakStmt Nothing):xs)) = return Break
evalStmt env (BlockStmt (x:xs)) = do
    result <- evalStmt env x
    case result of
        (Return a) -> return (Return a)
        (Break) -> return Break
        _ -> evalStmt env (BlockStmt xs) 



evalStmt env (ForStmt init maybeComp maybeIncrement statements) = do
    evalForInit env init
    case maybeComp of
        Nothing -> do
            a <-evalStmt env statements 
            case a of
                Break -> return Break
                _ -> case maybeIncrement of
                    Nothing -> evalStmt env (ForStmt NoInit Nothing Nothing statements) 
                    (Just incr) -> evalExpr env incr >>  (evalStmt env (ForStmt NoInit Nothing maybeIncrement statements))
        (Just comp) -> do
            ret <- evalExpr env comp
            case ret of
                (Bool b) -> if b then do
                   v <- evalStmt env statements
                   case v of
                    Break -> return Break; 
                    _ -> case maybeIncrement of
                        Nothing -> do
                             evalStmt env (ForStmt NoInit maybeComp Nothing statements)
                        (Just incr) -> do
                            evalExpr env incr
                            evalStmt env (ForStmt NoInit maybeComp maybeIncrement statements)
                else return Nil


		
evalIf :: StateT -> Expression -> Statement -> StateTransformer Value
evalIf env expr v1 = do
	v <- evalExpr env expr
	case v of 
		err@(Error s) -> return err
		Bool b ->if b == True then evalStmt env v1 else return Nil
	
evalIfElse :: StateT -> Expression -> Statement -> Statement -> StateTransformer Value
evalIfElse env exp v1 v2 = do
	v <- evalExpr env exp
	case v of  
		err@(Error s) -> return err
		Bool b -> if b == True then evalStmt env v1 else evalStmt env v2
	
	
	

-- Do not touch this one :)
evaluate :: StateT -> [Statement] -> StateTransformer Value
evaluate env [] = return Nil
evaluate env [stmt] = evalStmt env stmt
evaluate env (s:ss) = evalStmt env s >> evaluate env ss

--
-- Operators
--

infixOp :: StateT -> InfixOp -> Value -> Value -> StateTransformer Value
infixOp env OpAdd  (Int  v1) (Int  v2) = return $ Int  $ v1 + v2
infixOp env OpSub  (Int  v1) (Int  v2) = return $ Int  $ v1 - v2
infixOp env OpMul  (Int  v1) (Int  v2) = return $ Int  $ v1 * v2
infixOp env OpDiv  (Int  v1) (Int  v2) = return $ Int  $ div v1 v2
infixOp env OpMod  (Int  v1) (Int  v2) = return $ Int  $ mod v1 v2
infixOp env OpLT   (Int  v1) (Int  v2) = return $ Bool $ v1 < v2
infixOp env OpLEq  (Int  v1) (Int  v2) = return $ Bool $ v1 <= v2
infixOp env OpGT   (Int  v1) (Int  v2) = return $ Bool $ v1 > v2
infixOp env OpGEq  (Int  v1) (Int  v2) = return $ Bool $ v1 >= v2
infixOp env OpEq   (Int  v1) (Int  v2) = return $ Bool $ v1 == v2
infixOp env OpNEq  (Bool v1) (Bool v2) = return $ Bool $ v1 /= v2
infixOp env OpLAnd (Bool v1) (Bool v2) = return $ Bool $ v1 && v2
infixOp env OpLOr  (Bool v1) (Bool v2) = return $ Bool $ v1 || v2

infixOp env op (Var x) v2 = do
    var <- stateLookup env x
    case var of
        error@(Error _) -> return error
        val -> infixOp env op val v2

infixOp env op v1 (Var x) = do
    var <- stateLookup env x
    case var of
        error@(Error _) -> return error
        val -> infixOp env op v1 val

--
-- Environment and auxiliary functions
--

environment :: Map String Value
environment = empty

stateLookup :: StateT -> String -> StateTransformer Value
stateLookup env var = ST $ \s ->
    (maybe
        (Error $ "Variable " ++ show var ++ " not defined")
        id
        (Map.lookup var (union s env)),
    s)

varDecl :: StateT -> VarDecl -> StateTransformer Value
varDecl env (VarDecl (Id id) maybeExpr) = do
    case maybeExpr of
        Nothing -> setVar id Nil
        (Just expr) -> do
            val <- evalExpr env expr
            setVar id val

setVar :: String -> Value -> StateTransformer Value
setVar var val = ST $ \s -> (val, insert var val s)

--
-- Types and boilerplate
--

type StateT = Map String Value
data StateTransformer t = ST (StateT -> (t, StateT))

instance Monad StateTransformer where
    return x = ST $ \s -> (x, s)
    (>>=) (ST m) f = ST $ \s ->
        let (v, newS) = m s
            (ST resF) = f v
        in resF newS

instance Functor StateTransformer where
    fmap = liftM

instance Applicative StateTransformer where
    pure = return
    (<*>) = ap

--
-- Main and results functions
--

showResult :: (Value, StateT) -> String
showResult (val, defs) = show val ++ "\n" ++ show (toList defs) ++ "\n"

getResult :: StateTransformer Value -> (Value, StateT)
getResult (ST f) = f empty

main :: IO ()
main = do
    js <- Parser.parseFromFile "Main.js"
    let statements = unJavaScript js
    putStrLn $ "AST: " ++ (show $ statements) ++ "\n"
    putStr $ showResult $ getResult $ evaluate environment statements
