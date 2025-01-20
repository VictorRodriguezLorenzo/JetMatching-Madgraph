import os
import optparse
import math

# Class defining text formatting for colored console output using ANSI escape codes.
class bcolors:
    HEADER = '\033[95m'  # Purple for headers.
    OKBLUE = '\033[94m'  # Blue for informational messages.
    OKGREEN = '\033[92m'  # Green for success messages.
    WARNING = '\033[93m'  # Yellow for warnings.
    FAIL = '\033[91m'  # Red for errors or critical issues.
    ENDC = '\033[0m'  # Resets text formatting.
    BOLD = '\033[1m'  # Makes text bold.
    UNDERLINE = '\033[4m'  # Underlines text.

# Function to handle the submission of jobs.

def submit():
    # Print a decorative header indicating the start of the process.
    print(bcolors.HEADER)
    print('#######################################################################')
    print('                  Starting job(s) submission...                        ')
    print('#######################################################################' + bcolors.ENDC)

    # Setting up an option parser to handle command-line arguments.
    parser = optparse.OptionParser(usage='usage: %prog [opts]', version='%prog 1.0')

    # Adding options for various script parameters.
    parser.add_option('-q', '--queue', action='store', type=str, dest='queue', default='nextweek',
            help='Name of the queue to be used')
    parser.add_option('-c', '--qcut', action='store', type=str, dest='qcut',
            default="90",
            help='Value for qcut in pythia card')
    parser.add_option('-g', '--gridpack', action='store', type=str, dest='gridpack',
            default="/cvmfs/cms.cern.ch/phys_generator/gridpacks/2017/13TeV/madgraph/V5_2.6.1/ttbarDM_inclusive_DMsimp_LO/ttbarDM__dilepton__DMsimp_LO_ps_spin0__mchi_1_mphi_50_gSM_1_gDM_1_6500GeV_slc6_amd64_gcc630_CMSSW_9_3_8_tarball.tar.xz",
            help='Gridpack used for the study')   
    parser.add_option('-r', '--rootfile', action='store', type=str, dest='rootFileName',
            default="EXO-RunIIFall18GS",
            help='Output ROOT file name')
    parser.add_option('-o', '--output', action='store', type=str, dest='outputDir',
            default="/eos/user/v/victorr/CMSSW_13_2_9/src/Event_generation/",
            help='Output directory (EOS)')
    parser.add_option('-a', '--afs', action='store', type=str, dest='afsDir',
            default="/afs/cern.ch/user/v/victorr/private/CMSSW_13_2_9/src/logs/",
            help='Directory for logs and scripts (AFS)')
    parser.add_option('-w', '--work', action='store', type=str, dest='workDir', default=os.getcwd(),
            help='Working directory')
    parser.add_option('-n', '--events', action='store', type=int, dest='totalEvents', default=1000,
            help='Total number of events to process')
    parser.add_option('-e', '--eventsPerRun', action='store', type=int, dest='eventsPerRun', default=100,
            help='Number of events per run')
    parser.add_option('-t', '--test', action='store_true', dest='doNotSend', default=False,
            help='Do not send the jobs to the queue, for testing purposes')

    # Parsing command-line arguments.
    (opts, args) = parser.parse_args()

    # Reading the options provided by the user or falling back to defaults.
    queue = opts.queue
    eosDir = opts.outputDir  # Directory for output data (e.g., EOS).
    rootFileName = opts.rootFileName
    afsDir = opts.afsDir  # Directory for logs and submission scripts (e.g., AFS).
    workDir = opts.workDir  # User's working directory.
    totalEvents = opts.totalEvents  # Total number of events to process.
    eventsPerRun = opts.eventsPerRun  # Number of events processed per job.
    doNotSend = opts.doNotSend  # If True, jobs are created but not submitted.
    qcut = opts.qcut
    gridpack = opts.gridpack

    # Ensure required directories exist, creating them if necessary.
    if not os.path.exists(afsDir):
        os.makedirs(afsDir)
    if not os.path.exists(eosDir):
        os.makedirs(eosDir)

    # Calculate the number of jobs required based on total events and events per job.
    numRuns = math.ceil(totalEvents / eventsPerRun)

    # Print a summary of options and calculations.
    print(bcolors.OKBLUE)
    print('#######################################################################')
    print('                  Summary of options chosen                        ')
    print('#######################################################################')
    print(f"Queue: {queue}")
    print(f"Output directory (EOS): {eosDir}")
    print(f"AFS directory for logs and scripts: {afsDir}")
    print(f"Working directory: {workDir}")
    print(f"Total events: {totalEvents}")
    print(f"Events per run: {eventsPerRun}")
    print(f"Number of runs: {numRuns}")
    print('#######################################################################' + bcolors.ENDC)

    jobsList = []  # List to store all job names for batch submission.

    # Loop over each job to generate its script and submission files.
    for runIndex in range(numRuns):
        firstEvent = runIndex * eventsPerRun
        lastEvent = min((runIndex + 1) * eventsPerRun, totalEvents)

        jobName = f"job_{runIndex:03d}"  # Unique job name based on its index.
        jobsList.append(jobName)

        # Define paths for job scripts, logs, and submission files.
        jobFileName = os.path.join(afsDir, f"{jobName}.sh")
        subFileName = os.path.join(afsDir, f"{jobName}.sub")
        outFileName = os.path.join(afsDir, f"{jobName}.out")
        errFileName = os.path.join(afsDir, f"{jobName}.err")
        logFileName = os.path.join(afsDir, f"{jobName}.log")

        # Define the directory on EOS for the job's output.
        jobRunDir = os.path.join(eosDir, f"run_{runIndex}")

        # Create the job execution script.
        with open(jobFileName, "w") as jobFile:
            jobFile.write("#!/bin/bash\n")
#            jobFile.write("export X509_USER_PROXY=/afs/cern.ch/user/v/victorr/.proxy\n")  # Proxy setup.
#            jobFile.write("voms-proxy-info\n")  # Print proxy information for debugging.

            # Use the HTCondor scratch directory for temporary processing
            jobFile.write("TMPDIR=$_CONDOR_SCRATCH_DIR\n")
            jobFile.write("mkdir -p $TMPDIR\n")
            jobFile.write("cd $TMPDIR\n")

            jobFile.write(f"mkdir -p {jobRunDir}\n")  # Create the job-specific output directory in EOS.

            # Intialize CMSSW release within that folder
            jobFile.write("cmsrel CMSSW_13_2_9\n")
            jobFile.write("cd CMSSW_13_2_9/src\n")
            jobFile.write("cp -r /afs/cern.ch/user/v/victorr/private/tt_DM/full_workflow/CMSSW_13_2_9/src/Configuration .\n")
            # Update the gridpack path and qcut in the fragment
            jobFile.write(f"sed -i 's|\"gridpack_path\": \".*\.tar.xz\"|\"gridpack_path\": \"{gridpack}\"|' 'Configuration/GenProduction/python/EXO-RunIIFall18GS-test.py'\n")
            jobFile.write(f"sed -i 's/\\(JetMatching:qCut = \\)[0-9]\\+/\\1{qcut}/' 'Configuration/GenProduction/python/EXO-RunIIFall18GS-test.py'\n")
            jobFile.write("cat Configuration/GenProduction/python/EXO-RunIIFall18GS-test.py\n")
            jobFile.write("scram b\n")
            jobFile.write("cmsenv\n")


            # Run the CMS driver command for job execution in the temporary directory.
            jobFile.write(
                    f"cmsDriver.py Configuration/GenProduction/python/EXO-RunIIFall18GS-test.py "
                    f"-n {eventsPerRun} --fileout file:{rootFileName}-{jobName}.root --mc "
                    f"--eventcontent RAWSIM --datatier GEN-SIM --conditions 124X_mcRun3_2022_realistic_postEE_v1 "
                    f"--beamspot Realistic25ns13p6TeVEarly2022Collision "
                    f"--customise_commands \"process.source.numberEventsInLuminosityBlock = cms.untracked.uint32(50)\" "
                    f"--step GEN,SIM --geometry DB:Extended --era Run3\n"
                    )

            # Transfer the output file to the EOS directory
            jobFile.write(f"xrdcp {rootFileName}-{jobName}.root root://eosuser.cern.ch/{jobRunDir}\n")

        os.chmod(jobFileName, 0o755)  # Make the script executable.

        # Create the HTCondor submission file.
        with open(subFileName, "w") as subFile:
            subFile.write(f"executable = {jobFileName}\n")
            subFile.write("universe = vanilla\n")
            subFile.write(f"output = {outFileName}\n")
            subFile.write(f"error = {errFileName}\n")
            subFile.write(f"log = {logFileName}\n")
            subFile.write(f"+JobFlavour = \"{queue}\"\n")
            subFile.write("queue\n")  # Add the job to the queue.

# Generate a master submission script for all jobs.
    with open(os.path.join(afsDir, "all.sub"), "w") as allSub:
        #allSub.write('MY.SingularityImage = "/cvmfs/unpacked.cern.ch/gitlab-registry.cern.ch/cms-cat/cmssw-lxplus/cmssw-el7-lxplus:latest/"\n')
        allSub.write("executable = $(job).sh\n")
        allSub.write("universe = vanilla\n")
        allSub.write("output = $(job).out\n")
        allSub.write("error = $(job).err\n")
        allSub.write("log = $(job).log\n")
        allSub.write(f"+JobFlavour = \"{queue}\"\n")
        #allSub.write("request_cpus = 4\n")
        #allSub.write("request_memory = 4 GB\n")
        allSub.write("priority = -1\n")
        allSub.write("queue job in (\n")
        for jobName in jobsList:
            allSub.write(f"{os.path.join(afsDir, jobName)}\n")
        allSub.write(")\n")

    # Submit the jobs or notify the user if the test flag is set.
    if not doNotSend:
        os.system(f"condor_submit {os.path.join(afsDir, 'all.sub')}")
        print(f"Done! {numRuns} jobs have been submitted.\n")
    else:
        print(f"Done! {numRuns} jobs have been created but not submitted.\n")

# Entry point for the script.
if __name__ == "__main__":
    submit()
