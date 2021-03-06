
module Interactive where

import Semantics6

import qualified Data.Set as Set
import qualified Data.Map as Map

{-------------------------
 - Interactive interface -
 -------------------------}

 -- Interactively steps through the semantics,
 -- prompting the user for input at each stage, 
 -- by choosing from a set of options including
 --   - possible commits and reveals
 --   - stepping
 --   - advancing block number

 -- At each stage shows 
 --   - the remaining contract
 --   - internal state
 --   - actions generated

-- Information about the state of commits (for use by the interactive interface)
type CommitStates = [CommitState]
data CommitState = UncommittedCC CC | UncommittedCV CV [Value] |
                   CommittedCC CC | CommittedCV CV [Value] |
                   RedeemedCV CV -- | RedeemedCC CC     -- (for convenience we don't use this)
               deriving (Eq,Ord,Show,Read)

-- Main function of the interactive interface
interact_contract :: Contract -> IO (Contract, OS, State)
interact_contract c =
  interact_contract_loop initial_commit_states (Map.empty, Map.empty) initial_commits initial_obs c
  where initial_commit_states = Set.toList (extract_choices c)
        initial_commits = Commits Set.empty Set.empty Map.empty Set.empty
        initial_obs = OS 1 1 1

-- Main loop of the interactive interface
interact_contract_loop :: CommitStates -> State -> Commits -> OS -> Contract -> IO (Contract, OS, State)
interact_contract_loop comsta sta com obs c =
  do print_state sta com obs c
     print_options (options comsta com obs sta c)
     print_prompt
     (_, choice) <- read_option opts
     result <- choice
     case result of
        Just (ncomsta, ncom, nc, nobs, nsta, as) ->
              do print_actions as
                 interact_contract_loop ncomsta nsta ncom nobs nc
        Nothing -> (return (c, obs, sta))
  where opts = options comsta com obs sta c


-- Prints the options passed in the map
-- The key of the map is the trigger (the string to write at the prompt)
-- the first element of the value is the description of the option
print_options :: Map.Map String (String, a) -> IO ()

print_options opts = mapM_ (print_option) labels
    where labels = [(str, exp) | (str, (exp, ac)) <- Map.toList opts]

-- Prints a single option (first element is the trigger, second is the description)
print_option :: (String, String) -> IO ()

print_option (str, exp) = putStrLn (nstr ++ ") " ++ exp)
    where nstr = if (str == "") then "<ENTER>" else str

-- Prints a list of actions
print_actions :: AS -> IO ()

print_actions ac =
  if ((length ac) == 0) then (return ()) else
  do putStrLn ""
     putStrLn "***************"
     putStrLn "* ACTIONS !!! *"
     putStrLn "***************"
     putStrLn ""
     putStrLn ("The following action" ++ s ++ " required: " ++ (show ac))
  where s = if (length ac) == 1 then " is" else "s are"

-- Prints the state of the contract execution:
-- the contract remaining, the state, the commits received
-- and the current observables
print_state :: State -> Commits -> OS -> Contract -> IO ()

print_state sta com obs c =
  do putStrLn ""
     putStrLn "*********"
     putStrLn "* STATE *"
     putStrLn "*********"
     putStrLn ""
     putStrLn ("Remaining contract: " ++ (prettyprint_con_aux2 c 20))
     putStrLn ""
     putStrLn ("Internal state: " ++ (show sta))
     putStrLn ""
     putStrLn ("Commits provided: " ++ (show com))
     putStrLn ""
     putStrLn ("Observables provided: " ++ (show obs))
     putStrLn ""

-- Prints the prompt
print_prompt :: IO ()

print_prompt = putStr "> "

-- Reads a line until one of the keys of the map is input
-- returns the value of the map corresponding to the input 
read_option :: Map.Map String b -> IO b

read_option opts = do line <- getLine
                      case Map.lookup line opts of
                         Just op -> return op
                         Nothing -> do putStrLn "Option not valid\n"
                                       print_prompt
                                       read_option opts

-- Prints the options generated by generate_options together with
-- the three basic options (quit, advance step, and advance block)
options :: CommitStates -> Commits -> OS -> State -> Contract ->
           (Map.Map String (String, IO (Maybe (CommitStates, Commits, Contract, OS, State, AS))))

options comst com obs st con =
   Map.fromList ([("q", ("Quit", (return Nothing))),
                  ("1", ("Advance step", next_step_option comst com st con obs)),
                  ("", ("Advance block", next_block_option comst com st con obs))] ++
                  generate_options comst com obs st con option_accessors)

-- Generates the possible options by using the current state
-- (commit and redeem for cash and value commitments)
-- uses generate_options_aux and generate_option

generate_options :: [CommitState] -> Commits -> OS -> State -> Contract -> [String] ->
                    [(String, (String, IO (Maybe (CommitStates, Commits, Contract, OS, State, AS))))]

generate_options comst com obs st con oa = res
   where (_, res) = generate_options_aux comst com obs st con [] oa

generate_options_aux :: [CommitState] -> Commits -> OS -> State -> Contract ->
                        [CommitState] -> [String] ->
                        ([String], [(String, (String, IO (Maybe (CommitStates, Commits, Contract, OS, State, AS))))])

generate_options_aux [] _ _ _ _ _ oa = (oa, [])
generate_options_aux (e:t) com obs st con acc oa = (rnoa, final_options)
    where (noa, op) = (generate_option e t com obs st con acc oa)
          (rnoa, rest_options) = (generate_options_aux t com obs st con (e:acc) noa)
          final_options = case op of
                             Just x -> (x:rest_options)
                             Nothing -> rest_options


generate_option :: CommitState -> [CommitState] -> Commits -> OS -> State ->
                   Contract -> [CommitState] -> [String] ->
                   ([String], Maybe (String, (String, IO (Maybe (CommitStates, Commits, Contract, OS, State, AS)))))

generate_option (UncommittedCC cc2) t com obs st con acc (o:oa) =
    (oa, Just (o, ("Commit cash " ++ (show cc2), commit_cc cc2 com obs st con ((reverse acc) ++ ((CommittedCC cc2):t)))))
generate_option (UncommittedCV cv2 vals) t com obs st con acc (o:oa) =
    (oa, Just (o, ("Commit value " ++ (show cv2), commit_cv cv2 com obs st con ((reverse acc) ++ ((CommittedCV cv2 vals):t)))))
generate_option (CommittedCC cc2@(CC ident _ _ _)) t com obs st con acc (o:oa) =
        case Map.lookup ident ccs of
             Just (_,NotRedeemed val _) -> (oa, Just (o, ("Redeem cash commit" ++ (show cc2),
                                           reveal_cc cc2 com obs st con ((reverse acc) ++ ((CommittedCC cc2):t)) val)))
             _ -> (o:oa, Nothing)       --   we can try to redeem several times --^
        where
          (cvs,ccs) = st
generate_option (CommittedCV cv2 vals) t com obs st con acc (o:oa) =
    (oa, Just (o, ("Reveal value " ++ (show cv2), reveal_cv cv2 com obs st vals con ((reverse acc) ++ ((RedeemedCV cv2):t)))))
--generate_option (RedeemedCC cc2) t com obs st con acc oa = (oa, Nothing)
generate_option (RedeemedCV _) _ _ _ _ _ _ oa = (oa, Nothing)

-- Inserts a cash commit in the state
commit_cc :: CC -> Commits -> OS -> State -> Contract -> CommitStates ->
             IO (Maybe (CommitStates, Commits, Contract, OS, State, AS))

commit_cc cc2 com obs st con comst =
     return (Just (comst, (com {cc = (Set.insert cc2 (cc com))}), con, obs, st, []))

-- Inserts a value commit in the state
commit_cv :: CV -> Commits -> OS -> State -> Contract -> CommitStates ->
             IO (Maybe (CommitStates, Commits, Contract, OS, State, AS))

commit_cv cv2 com obs st con comst =
     return (Just (comst, (com {cv = (Set.insert cv2 (cv com))}), con, obs, st, []))

-- Inserts a cash reveal in the state
reveal_cc :: CC -> Commits -> OS -> State -> Contract -> CommitStates -> Value ->
             IO (Maybe (CommitStates, Commits, Contract, OS, State, AS))

reveal_cc (CC ident per _ exp) com obs st con comst val =
     return (Just (comst, (com {rc = (Set.insert (RC ident val) (rc com))}), con, obs, st, []))

-- Asks for a value and inserts it as a value reveal
reveal_cv :: CV -> Commits -> OS -> State -> [Value] -> Contract -> CommitStates ->
             IO (Maybe (CommitStates, Commits, Contract, OS, State, AS))
reveal_cv (CV ident per) com obs st vals con comst =
  do putStrLn "Please introduce the value revealed."
     val <- getLine
     if (elem val $ map (show) vals) then
       return (Just (comst, (com {rv = (Map.insert ident (read val) (rv com))}),
                     con, obs, st, []))
     else (do putStrLn ("Wrong value! It must be in the list: " ++ (show vals) ++ ". Please try again.")
              reveal_cv (CV ident per) com obs st vals con comst)

-- Repeatedly calls the step function (full_step function actually) until
-- it does not change anything or produces any actions

compute_all :: Commits -> State -> Contract -> OS -> (State, Contract, AS)

compute_all com st con os = compute_all_aux com st con os []

compute_all_aux :: Commits -> State -> Contract -> OS -> AS -> (State, Contract, AS)

compute_all_aux com st con os ac
  | (nst == st) && (ncon == con) && (nac == []) = (st, con, ac)
  | otherwise = compute_all_aux com nst ncon os (nac ++ ac)
  where (nst, ncon, nac) = full_step com st con os

-- Advances the contract execution as much as possible and moves to the next block

next_block_option :: CommitStates -> Commits -> State -> Contract -> OS ->
                     IO (Maybe (CommitStates, Commits, Contract, OS, State, AS))

next_block_option comst com st con obs = do (return (Just (comst, com, nc, nobs, ns, as)))
     where (ns, nc, as) = compute_all com st con obs
           nobs = obs {blockNumber = (blockNumber obs) + 1,
                       time = (time obs) + 1}

-- Advances the contract execution one single step

next_step_option :: CommitStates -> Commits -> State -> Contract -> OS ->
                     IO (Maybe (CommitStates, Commits, Contract, OS, State, AS))

next_step_option comst com st con obs = do (return (Just (comst, com, nc, obs, ns, as)))
     where (ns, nc, as) = full_step com st con obs

-- Generates triggers for using with options in the prompt

option_accessors :: [String]

option_accessors = [[x] | x <- ['2'..'9'] ++ ['a'..'p'] ++ ['r'..'z']] ++ (map (show) [10..])

-- Extract the commit information from the contract to provide
-- more concrete options for the prompt

extract_choices :: Contract -> Set.Set CommitState 

extract_choices c = extract_choices_aux c Set.empty

extract_choices_aux :: Contract -> Set.Set CommitState -> Set.Set CommitState

extract_choices_aux Null acc = acc
extract_choices_aux (Pay from to val con) acc = extract_choices_aux con acc
extract_choices_aux (Both con1 con2) acc = extract_choices_aux con2 (extract_choices_aux con1 acc)
extract_choices_aux (Choice obs conT conF) acc = extract_choices_aux conF (extract_choices_aux conT acc)
extract_choices_aux (When obs exp con con2) acc = extract_choices_aux con2 (extract_choices_aux con acc)
extract_choices_aux (CommitValue ident person values con) acc =
    extract_choices_aux con (Set.insert (UncommittedCV (CV ident person) values) acc)
extract_choices_aux (CommitCash ident person val timeout con) acc =
    extract_choices_aux con (Set.insert (UncommittedCC (CC ident person val timeout)) acc)
extract_choices_aux (RedeemCC ident con) acc = extract_choices_aux con acc
extract_choices_aux (RevealCV ident con) acc = extract_choices_aux con acc


{------------------------------
 - Provisional prettyprinting -
 ------------------------------}


-- Prettyprinting for contract
prettyprint_con :: Contract -> String
prettyprint_con x = prettyprint_con_aux x 0 False

prettyprint_con_aux :: Contract -> Int -> Bool -> String 
prettyprint_con_aux x n b
  | b && (x /= Null) = (take n $ repeat ' ') ++ "(" ++ (prettyprint_con_aux2 x (n + 1)) ++ ")"
  | otherwise = (take n $ repeat ' ') ++ (prettyprint_con_aux2 x n)

prettyprint_con_aux2 :: Contract -> Int -> String
prettyprint_con_aux2 (Null) n = "Null"
prettyprint_con_aux2 (RedeemCC icc con) n = "RedeemCC (" ++ (show icc) ++ ")\n" ++
                                        (prettyprint_con_aux con (n + 2) True)
prettyprint_con_aux2 (RevealCV icv con) n = "RevealCV (" ++ (show icv) ++ ")\n" ++
                                        (prettyprint_con_aux con (n + 2) True)
prettyprint_con_aux2 (Pay per1 per2 int con) n =
  "Pay (" ++ (show per1) ++ ") (" ++
             (show per2) ++ ") (" ++
             (show int) ++ ")\n" ++ (prettyprint_con_aux con (n + 2) True)
prettyprint_con_aux2 (Both con con2) n =
  "Both (" ++ (prettyprint_con_aux2 con (n + 6)) ++ ")\n" ++
              (prettyprint_con_aux con2 (n + 5) True)
prettyprint_con_aux2 (Choice obs con con2) n =
  "Choice (" ++ (prettyprint_obs_aux2 obs (n + 8)) ++ ")\n" ++
          (prettyprint_con_aux con (n + 7) True) ++ "\n" ++
          (prettyprint_con_aux con2 (n + 7) True)
prettyprint_con_aux2 (CommitValue idcv per vals con) n =
  "CommitValue ("  ++ (show idcv) ++ ") (" ++
                      (show vals) ++ ") (" ++
                      (show per) ++ ")\n" ++
          (prettyprint_con_aux con (n + 2) True)
prettyprint_con_aux2 (CommitCash idcc per int time con) n =
  "CommitCash ("  ++ (show idcc) ++ ") (" ++
                     (show per) ++ ") (" ++
                     (show int) ++ ") (" ++
                     (show time) ++ ")\n" ++
          (prettyprint_con_aux con (n + 2) True)
prettyprint_con_aux2 (When obs time con con2) n =
  "When (" ++ (prettyprint_obs_aux2 obs (n + 6)) ++ ") (" ++
              (show time) ++ ")\n" ++
              (prettyprint_con_aux con (n + 5) True) ++ "\n" ++
              (prettyprint_con_aux con2 (n + 5) True)

-- Prettyprinting for observations
prettyprint_obs :: Observation -> String
prettyprint_obs x = prettyprint_obs_aux x 0 False

prettyprint_obs_aux :: Observation -> Int -> Bool -> String 
prettyprint_obs_aux x n b
  | b = (take n $ repeat ' ') ++ "(" ++ (prettyprint_obs_aux2 x (n + 1)) ++ ")"
  | otherwise = (take n $ repeat ' ') ++ (prettyprint_obs_aux2 x n)

prettyprint_obs_aux2 :: Observation -> Int -> String 
prettyprint_obs_aux2 (AndObs obs obs2) n =
  "AndObs (" ++ (prettyprint_obs_aux2 obs (n + 8)) ++ ")\n" ++
              (prettyprint_obs_aux obs2 (n + 7) True)
prettyprint_obs_aux2 (OrObs obs obs2) n =
  "OrObs (" ++ (prettyprint_obs_aux2 obs (n + 7)) ++ ")\n" ++
              (prettyprint_obs_aux obs2 (n + 6) True)
prettyprint_obs_aux2 (NotObs obs) n =
  "NotObs (" ++ (prettyprint_obs_aux2 obs (n + 7)) ++ ")"
prettyprint_obs_aux2 x n = show x

