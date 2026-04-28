\# AGENTS.md



This repository is a standalone helper project for generating region-specific VisionEval model input folders from statewide inputs.



Do not modify:

\- C:/Users/Jameson.Clements/source/VisionEval-dev

\- C:/Users/Jameson.Clements/source/VE\_Models

\- Any source statewide model inputs

\- Any template model inputs



Only write generated model outputs under:

\- outputs/generated\_models/

\- outputs/reports/

\- outputs/logs/



Use R for implementation.



Prefer small, testable functions in R/.

Do not create one giant script.



The geography crosswalk is authoritative. Region membership must be derived from selected Mareas, then allowed Azones/Bzones/Czones must be derived from the filtered geography file.



Do not infer input geography automatically in the first implementation. Use metadata/input\_manifest.csv.



Fail loudly on ambiguous or invalid inputs.

