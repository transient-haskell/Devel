module Main where
import Data
import Vote
import FreeChooser
import System.Directory
import TCache(syncCache, refcache, Cache) 


main= do
  --crear proyecto
  let project="project11111111111111" 
  let email="pepe"
  let pass="3025" 
  removeDirectoryRecursive dataPath
  createDirectory "data"
  copyFile "DefaultConstitution.hs" "data/DefaultConstitution.hs"
  print "creating user"
  
  cgi1 [("op","vor"),("email", email),("pass", pass),("pass2", pass),("reg",""),("SCRIPT_NAME","/dist/build/-tmp")]
  print "creating project"
  cgi1 [("op","cre"),("oldname",""),("type","create"),("name",project),("pdescrip","desc"),("topics","t1,t2"),("users",""),("subjects",""),("ispublic","OFF"),("isvisible","OFF"),("OK","OK"),("email","pepe")]
  syncCache (refcache :: Cache ResourceVote) `debug` "sync"
  Rp pr <- justGetVResource $ Rp uProject{pname=project}
  print "proyecto creado"
  print pr

  --crear constitution
  cgi1 [("op","suc"),("type","modify"),("project",project),("backTo","userPage"),("name","Gro                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   up majorities"),("category","Constitutional"),("authors",""),("contentType","const")
        ,("content",
	  "-- This is the constitution"

	  ++"ProjectConf{"

	  ++"-- The categories of proposals"
	  ++"categories= [\"Ordinary\",\"Constitutional\"]"
	  ++",catMajorities=["
	  ++"Majorities"
	  ++"	--The percent of votes necessary for the approbal of a proposal"
	  ++"    	{percentAprobal= 50"
	  ++"        --Percent of total votes necessary for the votation to be valid"
	  ++"	,percentNecessary = 20"
	  ++"        --percent fo complaint votes to reject a proposal"
	  ++"	,percentComplaint = 20"
	  ++"        --number of days in wich the proposal is open for votation"
	  ++"	,votationTime = 30"
	  ++"        --time (in days) after votation before closing the proposal. 0 means forever"
	  ++"	,timeSpan = 0"
	  ++"   }"
	  ++"   ,Majorities"
	  ++"	-- The percent of votes necessary for the approbal of a proposal"
	  ++" 	{percentAprobal= 50"
	  
	  ++"	,percentNecessary = 50"
	  
	  ++"	,percentComplaint = 10"
	  
	  ++"	,votationTime = 30"
	  
	  ++"	,timeSpan = 0"
	  ++"   }"
	  ++" ]"

	  ++" ,percentNewUser = 75"
	  
	  ++" ,checkApprobal = Nothing)")
          ,("typeOption","choose"),("question","Do you agree with this proposal?"),("options","Yes\r\nNo\r"),("email","pepe")]
  syncCache (refcache :: Cache ResourceVote)
  
  Rs sub <- justGetVResource $ Rs uSubject{sname="Group majorities",prosname= project}
  print "Subject creado:"
  print sub
  