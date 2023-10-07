#!/apps/python3/3.10.0/bin/python3

import json
import re
SUPPORTED_PP = ['ALL_POTENTIAL', 'POTENTIAL', 'POTENTIAL_UZH', 'GTH_POTENTIALS', 'NLCC_POTENTIALS', 'ECP_POTENTIALS']
def generateCp2kValenceElectronsInformation(
    pseudoPotentialFile = 'GTH_POTENTIALS',
    pseudoPotentialPath = '/home/561/hm1876/cp2k/data/',
    functional = 'PBE',
    boolSmallCorePseudoPotential = True
):
    numberOfValenceElectronDict = {}
    if not SUPPORTED_PP.count(pseudoPotentialFile):
        print('ERROR> The pseudopotential file is not supported yet')
        raise RuntimeError
    elif pseudoPotentialFile == 'GTH_POTENTIALS' or pseudoPotentialFile == 'NLCC_POTENTIALS':
        pPFCase = 1
    elif pseudoPotentialFile == 'ECP_POTENTIALS':
        pPFCase = 2
    else:
        pPFCase = -1
        print('ERROR> Wrong code modification, check and debug please')
        raise RuntimeError
    
    def importNumberOfElectrons(element, qP):
        # abbr.: qPresent -> qP
        try:
            q = numberOfValenceElectronDict[element]
            if (
                q > qP and boolSmallCorePseudoPotential
                ) or (
                    q <= qP and not boolSmallCorePseudoPotential
                    ):
                numberOfValenceElectronDict[element] = qP
        except KeyError:
            numberOfValenceElectronDict[element] = qP

    with open(file = pseudoPotentialPath+pseudoPotentialFile, mode = 'r') as pseudo_f:
        line = 'start'
        while line:
            line = pseudo_f.readline()
            if line.startswith('#'):
                continue
            if re.match('^[A-Z]', string=line):
                words = line.split()
                if pPFCase == 1:
                    pseudoInformation = words[1]
                    presentElement = words[0]
                    pseudoInformationWords = pseudoInformation.split('-')
                    qPresent = int(pseudoInformationWords[-1][1::])
                    if pseudoInformationWords[-2] == functional:
                        # GTH_POTENTIALS format: GTH-PBE-qX
                        # NLCC_POTENTIALS format: GTH-NLCC-PBE-qX
                        '''
                        try:
                            q = numberOfValenceElectronDict[presentElement]
                            if (
                                q > qPresent and boolSmallCorePseudoPotential
                                ) or (
                                    q <= qPresent and not boolSmallCorePseudoPotential
                                    ):
                                numberOfValenceElectronDict[presentElement] = qPresent
                        except KeyError:
                            numberOfValenceElectronDict[presentElement] = qPresent
                        '''
                        importNumberOfElectrons(presentElement, qPresent)
                elif pPFCase == 2:
                    if len(words) < 3:
                        continue
                    else:
                        presentElement = words[0]
                        qPresent = int(words[-1])
                        importNumberOfElectrons(presentElement, qPresent)

    if boolSmallCorePseudoPotential:
        if pPFCase == 1:
            jsonFileName = pseudoPotentialFile+'-'+functional+'-SmallCore.json'
        else:
            jsonFileName = pseudoPotentialFile+'-'+'-SmallCore.json'
    else:
        if pPFCase == 1:
            jsonFileName = pseudoPotentialFile+'-'+functional+'-BigCore.json'
        else:
            jsonFileName = pseudoPotentialFile+'-'+'-BigCore.json'
    with open(jsonFileName, mode = 'w', encoding = 'utf-8') as json_f:
        json.dump(numberOfValenceElectronDict, json_f, indent = 2)

if __name__ == "__main__":
    import sys
    if len(sys.argv) == 5:
        pPF = sys.argv[1]
        pPP = sys.argv[2]
        f = sys.argv[3]
        str_bSCPP = sys.argv[4]
        print('INFO> Cp2k pseudoptential file reader for generating number of valence electrons is called.')
        runtimeInformation = 'INFO> Cp2k Pseudopotential File to parse: '+pPF+'\n'
        runtimeInformation+= 'INFO> Path to find this file: '+pPP+'\n'
        runtimeInformation+= 'INFO> Functional chosen: '+f+'\n'
        runtimeInformation+= 'INFO> Small core pseudopotential? '+str_bSCPP
        print(runtimeInformation)
        if str_bSCPP == 'False':
            bSCPP = False
        else:
            bSCPP = True
        generateCp2kValenceElectronsInformation(
            pseudoPotentialFile=pPF,
            pseudoPotentialPath=pPP,
            functional=f,
            boolSmallCorePseudoPotential=bSCPP
        )
    else:
        generateCp2kValenceElectronsInformation(boolSmallCorePseudoPotential=False)
