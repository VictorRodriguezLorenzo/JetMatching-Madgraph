import FWCore.ParameterSet.Config as cms

from Configuration.Generator.Pythia8CommonSettings_cfi import *
#from Configuration.Generator.MCTunes2017.PythiaCP5Settings_cfi import *
from Configuration.Generator.MCTunesRun3ECM13p6TeV.PythiaCP5Settings_cfi import *
from Configuration.Generator.PSweightsPythia.PythiaPSweightsSettings_cfi import *

generator = cms.EDFilter("Pythia8GeneratorFilter",
    maxEventsToPrint = cms.untracked.int32(1),
    pythiaPylistVerbosity = cms.untracked.int32(1),
    filterEfficiency = cms.untracked.double(1.0),
    pythiaHepMCVerbosity = cms.untracked.bool(False),
    comEnergy = cms.double(13600.),
    RandomizedParameters = cms.VPSet(),
)

grid_points = [{"gridpack_path": "/afs/cern.ch/user/v/victorr/private/tt_DM/full_workflow/gridpacks/dilepton__DMsimp_LO_ps_spin0__mchi_1_mphi_100_gSM_1_gDM_1_6800GeV/ttbarDM__dilepton__DMsimp_LO_ps_spin0__mchi_1_mphi_100_gSM_1_gDM_1_6800GeV_xqcut_20.tar.xz", "processParameters": ["JetMatching:setMad = off", "JetMatching:scheme = 1", "JetMatching:merge = on", "JetMatching:jetAlgorithm = 2", "JetMatching:etaJetMax = 5.", "JetMatching:coneRadius = 1.", "JetMatching:slowJetPower = 1", "JetMatching:qCut = 90", "JetMatching:nQmatch = 5", "JetMatching:nJetMax = 1", "JetMatching:doShowerKt = off", "Check:epTolErr = 0.0003", "SLHA:minMassSM = 0.1"], "name": "/TTbarDMJets_Dilepton_pseudoscalar_LO_Mchi-40_Mphi-100_TuneCP5_13TeV-madgraph-mcatnlo-pythia8", "weight": 0.05325443786982249}]

for grid_point in grid_points:
	basePythiaParameters = cms.PSet(
		pythia8CommonSettingsBlock,
		pythia8CP5SettingsBlock,
		pythia8PSweightsSettingsBlock,
		processParameters = cms.vstring(grid_point['processParameters']),
		parameterSets = cms.vstring(
			"pythia8CommonSettings",
			"pythia8CP5Settings",
			"pythia8PSweightsSettings",
			'processParameters',
		),
	)

	generator.RandomizedParameters.append(
		cms.PSet(
            ConfigWeight = cms.double(grid_point['weight']),
            ConfigDescription = cms.string(grid_point['name']),
            PythiaParameters = basePythiaParameters,
		GridpackPath = cms.string(grid_point['gridpack_path']),

		)
	)

ProductionFilterSequence = cms.Sequence(generator)             
