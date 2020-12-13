#!/bin/bash

# ------------------------------------------------------------------
### Set up GEOS-Chem for Jacobian run (mps, 2/20/2020)
# ------------------------------------------------------------------

##=======================================================================
## Set variables

# Path to inversion setup
INV_PATH=$(pwd -P)

# Name for this run
RUN_NAME="Test_NA"

# Path where you want to set up CH4 inversion code and run directories
MY_PATH="/n/holyscratch01/jacob_lab/msulprizio/CH4"

# Path to find non-emissions input data
DATA_PATH="/n/holyscratch01/external_repos/GEOS-CHEM/gcgrid/gcdata/ExtData"

# Path to initial restart file
RESTART_FILE="${MY_PATH}/input_data_permian/GEOSChem.Restart.fromBC.20180401_0000z.nc4"

# Path to boundary condition files (for nested grid simulations)
# Must put backslash before $ in $YYYY$MM$DD to properly work in sed command
BC_FILES="${MY_PATH}/input_data_permian/Lu_BC_CH4/GEOSChem.BoundaryConditions.\$YYYY\$MM\$DD_0000z.nc4"

# Do spinup simulation?
DO_SPINUP=true
SPINUP_START=20180401
SPINUP_END=20180501

# Start and end date fo the production simulations
START_DATE=20180501
END_DATE=20180601

# Grid settings (Global 4x5)
#RES="4x5"
#MET="merra2"
#LONS="-180.0 180.0"
#LATS=" -90.0  90.0"
#HPOLAR="T"
#LEVS="47"
#NEST="F"
#REGION=""
#BUFFER="0 0 0 0"

# Grid settings (Nested NA)
RES="0.5x0.625"
MET="merra2"
LONS="-140.0 -40.0"
LATS="  10.0  70.0"
HPOLAR="F"
LEVS="47"
NEST="T"
REGION="NA"  # NA,AS,CH,EU
BUFFER="3 3 3 3"

# Jacobian settings
nClusters=2 #243
pPERT="1.5"

# Turn on observation operators and planeflight diagnostics?
GOSAT=false
TCCON=false
UseEmisSF=false
UseSeparateWetlandSF=false
UseOHSF=false
PLANEFLIGHT=false
HourlyCH4=true

##=======================================================================
## Define met and grid fields for HEMCO_Config.rc
if [ "$MET" == "geosfp" ]; then
  metDir="GEOS_FP"
  native="0.25x0.3125"
elif [ "$MET" == "merra2" ]; then
  metDir="MERRA2"
  native="0.5x0.625"
fi
if [ "$RES" = "4x5" ]; then
    gridRes="4.0x5.0"
elif [ "$RES" == "2x2.5" ]; then
    gridRes="2.0x2.5"
else
    gridRes="$RES"
fi
if [ -z "$REGION" ]; then
    gridDir="$RES"
else
    gridDir="${RES}_${REGION}"
fi

##=======================================================================
## Copy run directory files directly from GEOS-Chem repository
GCC_RUN_FILES="${INV_PATH}/GEOS-Chem/run/GCClassic"
mkdir -p ${MY_PATH}/${RUN_NAME}
cd ${MY_PATH}/$RUN_NAME
mkdir -p jacobian_runs
cp ${GCC_RUN_FILES}/runScriptSamples/submit_array_jobs jacobian_runs/
sed -i -e "s:{RunName}:${RUN_NAME}:g" jacobian_runs/submit_array_jobs
cp ${GCC_RUN_FILES}/runScriptSamples/run_array_job jacobian_runs/
sed -i -e "s:{START}:0:g" -e "s:{END}:${nClusters}:g" jacobian_runs/run_array_job
cp ${GCC_RUN_FILES}/runScriptSamples/rundir_check.sh jacobian_runs/

RUN_TEMPLATE="template_run"
mkdir -p ${RUN_TEMPLATE}
cp -RLv ${GCC_RUN_FILES}/input.geos.templates/input.geos.CH4 ${RUN_TEMPLATE}/input.geos
cp -RLv ${GCC_RUN_FILES}/HISTORY.rc.templates/HISTORY.rc.CH4 ${RUN_TEMPLATE}/HISTORY.rc
cp -RLv ${GCC_RUN_FILES}/runScriptSamples/run.template ${RUN_TEMPLATE}
cp -RLv ${GCC_RUN_FILES}/getRunInfo ${RUN_TEMPLATE}/
cp -RLv ${GCC_RUN_FILES}/Makefile ${RUN_TEMPLATE}/
cp -RLv ${GCC_RUN_FILES}/HEMCO_Diagn.rc.templates/HEMCO_Diagn.rc.CH4 ${RUN_TEMPLATE}/HEMCO_Diagn.rc
if [ "$NEST" == "T" ]; then
    cp -RLv ${GCC_RUN_FILES}/HEMCO_Config.rc.templates/HEMCO_Config.rc.CH4_na ${RUN_TEMPLATE}/HEMCO_Config.rc
else
    cp -RLv ${GCC_RUN_FILES}/HEMCO_Config.rc.templates/HEMCO_Config.rc.CH4 ${RUN_TEMPLATE}/HEMCO_Config.rc
fi

##=======================================================================
## Set up template run directory
cd $RUN_TEMPLATE
mkdir -p OutputDir
mkdir -p Restarts

### Update settings in input.geos
sed -i -e "s:{DATE1}:${START_DATE}:g" \
       -e "s:{DATE2}:${END_DATE}:g" \
       -e "s:{TIME1}:000000:g" \
       -e "s:{TIME2}:000000:g" \
       -e "s:{MET}:${MET}:g" \
       -e "s:{DATA_ROOT}:${DATA_PATH}:g" \
       -e "s:{SIM}:CH4:g" \
       -e "s:{RES}:${gridRes}:g" \
       -e "s:{LON_RANGE}:${LONS}:g" \
       -e "s:{LAT_RANGE}:${LATS}:g" \
       -e "s:{HALF_POLAR}:${HPOLAR}:g" \
       -e "s:{NLEV}:${LEVS}:g" \
       -e "s:{NESTED_SIM}:${NEST}:g" \
       -e "s:{BUFFER_ZONE}:${BUFFER}:g" input.geos
if [ "$NEST" == "T" ]; then
    echo "Replacing timestep"
    sed -i -e "s|timestep \[sec\]: 600|timestep \[sec\]: 300|g" \
           -e "s|timestep \[sec\]: 1200|timestep \[sec\]: 600|g" input.geos
fi

# For CH4 inversions always turn analytical inversion on
OLD="Do analytical inversion?: F"
NEW="Do analytical inversion?: T"
sed -i "s/$OLD/$NEW/g" input.geos

# Turn other options on/off according to settings above
if "$GOSAT"; then
    OLD="Use GOSAT obs operator? : F"
    NEW="Use GOSAT obs operator? : T"
    sed -i "s/$OLD/$NEW/g" input.geos
fi
if "$TCCON"; then
    OLD="Use TCCON obs operator? : F"
    NEW="Use TCCON obs operator? : T"
    sed -i "s/$OLD/$NEW/g" input.geos
fi
if "$UseEmisSF"; then
    OLD=" => Use emis scale factr: F"
    NEW=" => Use emis scale factr: T"
    sed -i "s/$OLD/$NEW/g" input.geos
fi
if "$UseSeparateWetlandSF"; then
    OLD=" => Use sep. wetland SFs: F"
    NEW=" => Use sep. wetland SFs: T"
    sed -i "s/$OLD/$NEW/g" input.geos
fi
if "$UseOHSF"; then
    OLD=" => Use OH scale factors: F"
    NEW=" => Use OH scale factors: T"
    sed -i "s/$OLD/$NEW/g" input.geos
fi
if "$PLANEFLIGHT"; then
    mkdir -p Plane_Logs
    OLD="Turn on plane flt diag? : F"
    NEW="Turn on plane flt diag? : T"
    sed -i "s/$OLD/$NEW/g" input.geos
    OLD="Flight track info file  : Planeflight.dat.YYYYMMDD"
    NEW="Flight track info file  : Planeflights\/Planeflight.dat.YYYYMMDD"
    sed -i "s/$OLD/$NEW/g" input.geos
    OLD="Output file name        : plane.log.YYYYMMDD"
    NEW="Output file name        : Plane_Logs\/plane.log.YYYYMMDD"
    sed -i "s/$OLD/$NEW/g" input.geos
fi

### Set up HEMCO_Config.rc
### Use monthly emissions diagnostic output for now
sed -i -e "s:End:Monthly:g" \
       -e "s:{VERBOSE}:0:g" \
       -e "s:{WARNINGS}:1:g" \
       -e "s:{DATA_ROOT}:${DATA_PATH}:g" \
       -e "s:{GRID_DIR}:${gridDir}:g" \
       -e "s:{MET_DIR}:${metDir}:g" \
       -e "s:{NATIVE_RES}:${native}:g" \
       -e "s:\$ROOT/SAMPLE_BCs/v2019-05/CH4/GEOSChem.BoundaryConditions.\$YYYY\$MM\$DD_\$HH\$MNz.nc4:${BC_FILES}:g" HEMCO_Config.rc
if [ ! -z "$REGION" ]; then
    sed -i -e "s:\$RES:\$RES.${REGION}:g" HEMCO_Config.rc
fi
       
### Set up HISTORY.rc
### Use monthly output for now
sed -i -e "s:{FREQUENCY}:00000100 000000:g" \
       -e "s:{DURATION}:00000100 000000:g" \
       -e 's:'\''CH4:#'\''CH4:g' HISTORY.rc

# If turned on, save out hourly CH4 concentrations and pressure fields to
# daily files
if "$HourlyCH4"; then
    sed -i -e 's/SpeciesConc.frequency:      00000100 000000/SpeciesConc.frequency:      00000000 010000/g' \
	   -e 's/SpeciesConc.duration:       00000100 000000/SpeciesConc.duration:       00000001 000000/g' \
           -e 's/SpeciesConc.mode:           '\''time-averaged/SpeciesConc.mode:           '\''instantaneous/g' \
	   -e 's/#'\''LevelEdgeDiags/'\''LevelEdgeDiags/g' \
	   -e 's/LevelEdgeDiags.frequency:   00000100 000000/LevelEdgeDiags.frequency:   00000000 010000/g' \
	   -e 's/LevelEdgeDiags.duration:    00000100 000000/LevelEdgeDiags.duration:    00000001 000000/g' \
	   -e 's/LevelEdgeDiags.mode:        '\''time-averaged/LevelEdgeDiags.mode:        '\''instantaneous/g' HISTORY.rc
fi

### Compile GEOS-Chem and store executable in template run directory
#make realclean CODE_DIR=${INV_PATH}/GEOS-Chem
#make -j4 build BPCH_DIAG=y CODE_DIR=${INV_PATH}/GEOS-Chem
#fi

### Navigate back to top-level directory
cd ..

##=======================================================================
##  Setup spinup run directory
if "$DO_SPINUP"; then

    ### Define the run directory name
    spinup_name="${RUN_NAME}_Spinup"

    ### Make the directory
    runDir="spinup_run"
    mkdir -p ${runDir}

    ### Copy and point to the necessary data
    cp -r ${RUN_TEMPLATE}/*  ${runDir}
    cd $runDir

    ### Link to GEOS-Chem executable instead of having a copy in each run dir
    rm -rf geos
    ln -s ../../${RUN_TEMPLATE}/geos .

    # Link to restart file
    ln -s $RESTART_FILE GEOSChem.Restart.${SPINUP_START}_0000z.nc4
    
    ### Update settings in input.geos
    sed -i -e "s|${START_DATE}|${SPINUP_START}|g" \
           -e "s|${END_DATE}|${SPINUP_END}|g" \
	   -e "s|Do analytical inversion?: T|Do analytical inversion?: F|g" \
	   -e "s|pertpert|1.0|g" \
           -e "s|clustnumclustnum|0|g" input.geos

    ### Create run script from template
    sed -e "s:namename:${spinup_name}:g" run.template > ${spinup_name}.run
    chmod 755 ${spinup_name}.run

    ### Print diagnostics
    echo "CREATED: ${runDir}"
    
    ### Navigate back to top-level directory
    cd ..
fi

##=======================================================================
##  Create Jacobian run directories

# Initialize (x=0 is base run, i.e. no perturbation; x=1 is cluster=1; etc.)
x=0

# Create run directory for each cluster so we can apply perturbation to each
while [ $x -le $nClusters ];do

   ### Positive or negative perturbation
   PERT=$pPERT
   xUSE=$x

   ### Add zeros to string name
   if [ $x -lt 10 ]; then
      xstr="000${x}"
   elif [ $x -lt 100 ]; then
      xstr="00${x}"
   elif [ $x -lt 1000 ]; then
      xstr="0${x}"
   else
      xstr="${x}"
   fi

   ### Define the run directory name
   name="${RUN_NAME}_${xstr}"

   ### Make the directory
   runDir="./jacobian_runs/${name}"
   mkdir -p ${runDir}

   ### Copy and point to the necessary data
   cp -r ${RUN_TEMPLATE}/*  ${runDir}
   cd $runDir

   ### Link to GEOS-Chem executable instead of having a copy in each run dir
   rm -rf geos
   ln -s ../../${RUN_TEMPLATE}/geos .

   # Link to restart file
   if "$DO_SPINUP"; then
       ln -s ../../spinup_run/GEOS_Chem.Restart.${SPINUP_END}_0000z.nc4 GEOSChem.Restart.${START_DATE}_0000z.nc4
   else
       ln -s $RESTART_FILE GEOSChem.Restart.${START_DATE}_0000z.nc4
   fi
   
   ### Update settings in input.geos
   sed -i -e "s:pertpert:${PERT}:g" \
          -e "s:clustnumclustnum:${xUSE}:g" input.geos

   ### Create run script from template
   sed -e "s:namename:${name}:g" run.template > ${name}.run
   chmod 755 ${name}.run

   ### Navigate back to top-level directory
   cd ../..

   ### Increment
   x=$[$x+1]

   ### Print diagnostics
   echo "CREATED: ${runDir}"

done

echo "=== DONE CREATING JACOBIAN RUN DIRECTORIES ==="

exit 0