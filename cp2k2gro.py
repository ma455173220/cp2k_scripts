#!/usr/bin/env python3
import os
import sys
import math
import shutil
import numpy as np
from optparse import OptionParser

# Shared module cp2k_xyz.py: next to this script, else in PATH
_lib_dir = os.path.dirname(os.path.realpath(__file__))
if not os.path.isfile(os.path.join(_lib_dir, 'cp2k_xyz.py')) and shutil.which('cp2k_xyz.py'):
    _lib_dir = os.path.dirname(os.path.realpath(shutil.which('cp2k_xyz.py')))
sys.path.insert(0, _lib_dir)
try:
    from cp2k_xyz import iter_xyz
except ImportError:
    raise SystemExit("Wrong! cp2k_xyz.py not found (keep it next to this script or in PATH).")

class CP2K2GRO(object):
    def __init__(self, options):
        self.parse_options(options)
        
        self.masses= [1.00794,4.002602,6.941,9.012182,10.811,12.011,14.00674,\
             15.9994,18.9984032,20.1797,22.989768,24.3050,26.981539,28.0855,\
             30.97362,32.066,35.4527,39.948,39.0983,40.078,44.955910,47.88,\
              50.9415,51.9961,54.93085,55.847,58.93320,58.69,63.546,65.39,\
              69.723,72.61,74.92159,78.96,79.904,83.80,85.4678,87.62,88.90585,91.224,\
              92.90638,95.94,98,101.07,102.90550,106.42,107.8682,112.411,\
              114.82,118.710,121.75,127.60,126.90447,131.29,132.90543,137.327,138.9055,140.115,\
              140.90765,144.24,145,150.36,151.965,157.25,158.92534,162.50,\
              164.93032,167.26,168.93421,173.04,174.967,178.49,180.9479,\
              183.85,186.207,190.2,192.22,195.08,196.96654,200.59,204.3833,\
              207.2,208.98037,209,210.0,222,223,226.025,227.028,232.0381,\
              231.03588,238.0289,237.048,244.,243.,247.,247.,251.,252.,\
              257.,258.,259.,260.0]

        self.element=['H', 'He', 'Li', 'Be', 'B', 'C', 'N', 'O', 'F', 'Ne', 'Na', 'Mg',\
         'Al', 'Si', 'P', 'S', 'Cl', 'Ar', 'K', 'Ca', 'Sc', 'Ti', 'V', 'Cr',\
          'Mn', 'Fe', 'Co', 'Ni', 'Cu', 'Zn', 'Ga', 'Ge', 'As', 'Se', 'Br', \
          'Kr', 'Rb', 'Sr', 'Y', 'Zr', 'Nb', 'Mo', 'Tc', 'Ru', 'Rh', 'Pd', \
          'Ag', 'Cd', 'In', 'Sn', 'Sb', 'Te', 'I', 'Xe', 'Cs', 'Ba', 'La', \
          'Ce', 'Pr', 'Nd', 'Pm', 'Sm', 'Eu', 'Gd', 'Tb', 'Dy', 'Ho', 'Er', \
          'Tm', 'Yb', 'Lu', 'Hf', 'Ta', 'W', 'Re', 'Os', 'Ir', 'Pt', 'Au', \
          'Hg', 'Tl', 'Pb', 'Bi', 'Po', 'At', 'Rn', 'Fr', 'Ra', 'Ac', 'Th', \
          'Pa', 'U', 'Np', 'Pu', 'Am', 'Cm', 'Bk', 'Cf', 'Es', 'Fm', 'Md', 'No', 'Lr']        

    def parse_options(self, options):
        if options.xyz == None:
            self.xyz="cp2k-pos-1.xyz"  
        else:
            self.xyz = options.xyz
            
        if not os.path.exists(self.xyz):
            raise SystemExit("Wrong! %s not found. -h for help." % (self.xyz))

        if options.velocity == None:
            self.velocity_ = None  
        else:
            self.velocity_ = options.velocity
            print("Velocity unit is Bohr/a.u. time")
            if not os.path.exists(self.velocity_):
                raise SystemExit("Wrong! %s not found. -h for help." % (self.velocity_))
            with open(self.velocity_,'r') as reader1, open(self.xyz,'r') as reader2:
                line_num1 = 0
                line_num2 = 0
                for i in reader1:
                    line_num1+=1
                for i in reader2:
                    line_num2+=1
                if line_num1 != line_num2:
                    raise SystemExit("Velocity output frequency may be not compatible with coordinates.")
                    
        self._cell_fix = False
        
        if options.cell == None:
            if not os.path.exists("cp2k-1.cell"):
                if not os.path.exists("CELL"):
                    with open("CELL",'w') as writer:
                        writer.write("# Input like this:\n# A B C\n# ALPHA BETA GAMMA\n")
                    raise SystemExit("Wrong! Cell parameters are needed. \nNVT ensemble is assumed. Fill in cell informations in the FILE [CELL], and rerun this script.")
                else:
                    try:
                        cells = np.loadtxt("CELL", comments='#')
                        if cells.shape != (2,3):
                            raise SystemExit("Wrong cell parameters!")
                        self.cells =  self.abc_to_hmatrix(cells[0][0],cells[0][1],cells[0][2],cells[1][0],cells[1][1],cells[1][2],True)  
                        self._cell_fix = True

                    except:
                        raise SystemExit("Wrong cell parameters!")
            else:
                self.cell = "cp2k-1.cell"
                if not os.path.exists(self.cell):
                    raise SystemExit("Wrong! %s not found." % (self.cell))
                    
        else:
            self.cell = options.cell
            if not os.path.exists(self.cell):
                raise SystemExit("Wrong! %s not found." % (self.cell))

        if options.gro_name == None:
            self.gro_name="system.gro"  
        else:
            # remove a trailing ".gro" suffix (rstrip would strip characters)
            gro_base = options.gro_name
            if gro_base.endswith(".gro"):
                gro_base = gro_base[:-len(".gro")]
            self.gro_name = gro_base + ".gro"
                        
        if os.path.exists(self.gro_name):
            os.remove(self.gro_name)

        if not options.mdp_top:
            self.mdp_top = False
        else:
            self.mdp_top = True         
    
    @staticmethod
    def abc_to_hmatrix(a, b, c, alpha, beta, gamma, degrees=True):
        if degrees:
            alpha, beta, gamma = map(math.radians, (alpha, beta, gamma))

        bc2 = b**2 + c**2 - 2*b*c*math.cos(alpha)
        h1 = a
        h2 = b * math.cos(gamma)
        h3 = b * math.sin(gamma)
        h4 = c * math.cos(beta)
        h5 = ((h2 - h4)**2 + h3**2 + c**2 - h4**2 - bc2)/(2 * h3)
        h6 = math.sqrt(c**2 - h4**2 - h5**2)
        return np.array([[h1, 0., 0.], [h2, h3, 0.], [h4, h5, h6]])
        
    def write_mdp_top(self):
        all_element__=list(set([i[0] for i in self.atoms]))
        tobe_writen=""
        tobe_writen+="; WARNING, it cannot be used for a simulation.\n\n"
        tobe_writen+="[ defaults ]\n; nbfunc comb-rule gen-pairs fudgeLJ fudgeQQ\n1 3 yes 0.5 0.5\n\n"
        tobe_writen+="[ atomtypes ]\n; name bond_type mass charge ptype sigma epsilon\n"
        for i in all_element__:
            tobe_writen+="%s C 1.0 0.0 A 0.0 0.0\n" %(i)
        tobe_writen+="\n"
        tobe_writen+="[ bondtypes ]\n;; i j func b0 kb\nC C 1 0.13 1000.0 ; totally bogus\n\n"
        tobe_writen+="[ angletypes ]\n; i j k func th0 cth\n  C C C 1 109.500 100.0 ; totally bogus\n\n"
        tobe_writen+="[ dihedraltypes ]\n; i j k l func coefficients\n  C C C C 1 0.0 3 10.0 ; totally bogus\n\n"
        tobe_writen+="[ moleculetype ]\n; Name      nrexcl\nmolecule0     3\n\n"
        tobe_writen+="[ atoms ]\n; nr  type  resnr residue atom cgnr charge  mass\n"
        ii = 1
        for i in self.atoms:
            tobe_writen+="%6d%12s      1      MOL%7s%6d     0.0000%11.4f\n" %(ii,i[0],i[0],ii,self.elementmass(i[0]))
            ii+=1
        tobe_writen+="\n"
        tobe_writen+="[ bonds ]\n; i  j  func\n\n[ system ]\n; Name\nMymolecule0\n\n"
        tobe_writen+="[ molecules ]\n; Compound    #mols\nmolecule0    1\n"
        
        with open(self.gro_name[:-len(".gro")] + ".top",'w') as writer:
            writer.write(tobe_writen)
            
        with open(self.gro_name[:-len(".gro")] + ".mdp",'w') as writer:
          
            writer.write("; minim.mdp - used as input into grompp to generate em.tpr\n")
            writer.write("integrator  = steep     ; Algorithm (steep = steepest descent minimization)\n")
            writer.write("emtol       = 1000.0    ; Stop minimization when the maximum force < 1000.0 kJ/mol/nm\n")
            writer.write("emstep      = 0.01      ; Energy step size\n")
            writer.write("nsteps      = 50000     ; Maximum number of (minimization) steps to perform\n")
            writer.write("\n")
            writer.write("; Parameters describing how to find the neighbors of each atom and how to calculate the interactions\n")
            writer.write("nstlist         = 1         ; Frequency to update the neighbor list and long range forces\n")
            writer.write("cutoff-scheme   = Verlet\n")
            writer.write("ns_type         = grid      ; Method to determine neighbor list (simple, grid)\n")
            writer.write("coulombtype     = cut-off       ; Treatment of long range electrostatic interactions\n")
            writer.write("rcoulomb        = 0.01       ; Short-range electrostatic cut-off\n")
            writer.write("rvdw            = 0.01       ; Short-range Van der Waals cut-off\n")
            writer.write("pbc             = xyz       ; Periodic Boundary Conditions (yes/no)\n\n")

    def lattice_at(self, time):
        """Cell (3 vectors) at the given time: fixed cell, or the row of the .cell file with that time."""
        if self._cell_fix:
            return self.cells
        if not hasattr(self, '_cell_by_time'):
            # first row for every time (dictionary: one lookup per frame instead of a scan of all rows)
            self._cell_by_time = {}
            for row in self.cells.tolist():
                self._cell_by_time.setdefault(row[1], row)
        try:
            lattice_infos = self._cell_by_time[time]
        except KeyError:
            raise SystemExit("Wrong!, time interval in cell is large than that in xyz files.")
        newlattice=[]
        newlattice.append(list(map(float,lattice_infos[2:5])))
        newlattice.append(list(map(float,lattice_infos[5:8])))
        newlattice.append(list(map(float,lattice_infos[8:11])))
        return newlattice

    @staticmethod
    def frame_atoms(frame):
        atoms=[]
        for line in frame.atom_lines:
            info=line.split()
            atoms.append((info[0],list(map(float,info[1:]))))
        return atoms

    def read_xyz(self):
        atoms = []
        for frame in iter_xyz(self.xyz):
            time=float(frame.comment.split()[5].strip(","))
            newlattice = self.lattice_at(time)
            atoms = self.frame_atoms(frame)
            self.write_gro(self.gro_name, time, atoms, newlattice)
        self.atoms = atoms

    def read_xyz_velocity(self):
        atoms = []
        for frame, vframe in zip(iter_xyz(self.xyz), iter_xyz(self.velocity_)):
            time=float(frame.comment.split()[5].strip(","))
            newlattice = self.lattice_at(time)
            atoms = self.frame_atoms(frame)
            atoms_vel=[]
            for line in vframe.atom_lines:
                info=line.split()
                atom_vel=list(map(lambda x: float(x)*2187.6912546085964 ,info[1:]))
                atoms_vel.append(atom_vel)
            self.write_gro_vel(self.gro_name, time, atoms, newlattice,atoms_vel)
        self.atoms = atoms
            
    def read_cell(self):
        cells=np.loadtxt(self.cell)
        if len(cells.shape) == 1:
            cells = cells[np.newaxis,:]
        return cells
    
    @staticmethod
    def write_gro(gro_name, time, atoms, newlattice):
        with open(gro_name,'a+') as writer:
            writer.write("t= %11.4f\n%d\n" %(time/1000.0,len(atoms))) #//ps
            ind=1
            for i in atoms:
                writer.write("%5d%-5s%5s%5d%8.3f%8.3f%8.3f\n" %(ind,"MOL",i[0],ind,i[1][0]/10.0,i[1][1]/10.0,i[1][2]/10.0))
                ind+=1
            writer.write("%8.4f%8.4f%8.4f%8.4f%8.4f%8.4f%8.4f%8.4f%8.4f\n" %(newlattice[0][0]/10.0,newlattice[1][1]/10.0,
            newlattice[2][2]/10.0,0.0,0.0,newlattice[1][0]/10.0,0.0,newlattice[2][0]/10.0,newlattice[2][1]/10.0))
        #v1(x) v2(y) v3(z) v1(y) v1(z) v2(x) v2(z) v3(x) v3(y), the last 6 values may be omitted (they will be set to zero). GROMACS only supports boxes with v1(y)=v1(z)=v2(z)=0. 

    @staticmethod
    def write_gro_vel(gro_name, time, atoms, newlattice,velocity):
        with open(gro_name,'a+') as writer:
            writer.write("t= %11.4f\n%d\n" %(time/1000.0,len(atoms))) #//ps
            ind=1
            for index,i in enumerate(atoms):
                writer.write("%5d%-5s%5s%5d%8.3f%8.3f%8.3f%8.4f%8.4f%8.4f\n" %(ind,"MOL",i[0],ind,i[1][0]/10.0,i[1][1]/10.0,i[1][2]/10.0,velocity[index][0],velocity[index][1],velocity[index][2]))
                ind+=1
            writer.write("%8.4f%8.4f%8.4f%8.4f%8.4f%8.4f%8.4f%8.4f%8.4f\n" %(newlattice[0][0]/10.0,newlattice[1][1]/10.0,
            newlattice[2][2]/10.0,0.0,0.0,newlattice[1][0]/10.0,0.0,newlattice[2][0]/10.0,newlattice[2][1]/10.0))
        #v1(x) v2(y) v3(z) v1(y) v1(z) v2(x) v2(z) v3(x) v3(y), the last 6 values may be omitted (they will be set to zero). GROMACS only supports boxes with v1(y)=v1(z)=v2(z)=0. 
        
    def elementmass(self, element_label):
        index=0
        for i in self.element:
            if i.upper()==element_label.upper():
                return self.masses[index]
            index+=1
    
    def convert_cp2k(self):       
        if not self._cell_fix: 
            self.cells = self.read_cell()
        if self.velocity_:
            self.read_xyz_velocity()
        else:    
            self.read_xyz()
        if self.mdp_top:
            self.write_mdp_top()
            
if __name__ == "__main__":
    parser = OptionParser()
    parser.add_option(
        "-x", "--xyz", dest="xyz",
        help="xyz filename"
    )

    parser.add_option(
        "-v", "--velocity", dest="velocity",
        help="velocity filename"
    )

    parser.add_option(
        "-c", "--cell", dest="cell",
        help="cell filename"
    )

    parser.add_option(
        "-f", "--filename", dest="gro_name",
        help="name for new gro file"
    )
        
    parser.add_option(
        "-a", "--all",
        action="store_true", dest="mdp_top", default=False,
        help="Generate mdp and top files."
    )
     
    (options, args) = parser.parse_args()   
     
    CP2K_object = CP2K2GRO(options)
    CP2K_object.convert_cp2k()
    
