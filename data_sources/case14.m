%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%                                                                  %%%%%
%%%%    IEEE PES Power Grid Library - Optimal Power Flow - v18.08     %%%%%
%%%%          (https://github.com/power-grid-lib/pglib-opf)           %%%%%
%%%%               Benchmark Group - Typical Operations               %%%%%
%%%%                        08 - August - 2018                        %%%%%
%%%%                                                                  %%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%   Power flow data for IEEE 14 bus test case.
%   This data was converted from IEEE Common Data Format
%   (ieee14cdf.txt) on 20-Sep-2004 by cdf2matp, rev. 1.11
%
%   Converted from IEEE CDF file from:
%        http://www.ee.washington.edu/research/pstca/
%
%   Copyright (c) 1999 by Richard D. Christie, University of Washington
%   Electrical Engineering Licensed under the Creative Commons Attribution 4.0
%   International license, http://creativecommons.org/licenses/by/4.0/
%
%   CDF Header:
%   08/19/93 UW ARCHIVE           100.0  1962 W IEEE 14 Bus Test Case
%
function mpc = pglib_opf_case14_ieee
mpc.version = '2';
mpc.baseMVA = 100.0;

%% bus data
%	bus_i	type	Pd	Qd	Gs	Bs	area	Vm	Va	baseKV	zone	Vmax	Vmin
mpc.bus = [
 		1.0000    3.0000         0         0         0         0    1.0000    1.0000         0    1.0000    1.0000    1.0600    0.9400
  	2.0000    2.0000   65.1000   38.1000         0         0    1.0000    1.0000         0    1.0000    1.0000    1.0600    0.9400
    3.0000    2.0000  282.6000   57.0000         0         0    1.0000    1.0000         0    1.0000    1.0000    1.0600    0.9400
    4.0000    1.0000  143.4000  -11.7000         0         0    1.0000    1.0000         0    1.0000    1.0000    1.0600    0.9400
    5.0000    1.0000   22.8000    4.8000         0         0    1.0000    1.0000         0    1.0000    1.0000    1.0600    0.9400
    6.0000    2.0000   33.6000   22.5000         0         0    1.0000    1.0000         0    1.0000    1.0000    1.0600    0.9400
    7.0000    1.0000         0         0         0         0    1.0000    1.0000         0    1.0000    1.0000    1.0600    0.9400
    8.0000    2.0000         0         0         0         0    1.0000    1.0000         0    1.0000    1.0000    1.0600    0.9400
    9.0000    1.0000   88.5000   49.8000         0   19.0000    1.0000    1.0000         0    1.0000    1.0000    1.0600    0.9400
   10.0000    1.0000   27.0000   17.4000         0         0    1.0000    1.0000         0    1.0000    1.0000    1.0600    0.9400
   11.0000    1.0000   10.5000    5.4000         0         0    1.0000    1.0000         0    1.0000    1.0000    1.0600    0.9400
   12.0000    1.0000   18.3000    4.8000         0         0    1.0000    1.0000         0    1.0000    1.0000    1.0600    0.9400
   13.0000    1.0000   40.5000   17.4000         0         0    1.0000    1.0000         0    1.0000    1.0000    1.0600    0.9400
   14.0000    1.0000   44.7000   15.0000         0         0    1.0000    1.0000         0    1.0000    1.0000    1.0600    0.9400
   15.0000    2.0000   0         0               0         0    1.0       1.0            0    1.0000    1.0000    1.0600    0.9400
];

%% generator data
%	bus	 Pg	    Qg	    Qmax	  Qmin	  Vg	mBase status Pmax	Pmin	Pc1	Pc2	Qc1min
%	Qc1max	Qc2min	Qc2max	ramp_agc	ramp_10	ramp_30	ramp_q	apf
%	type_tyndp
mpc.gen = [
	1	 170.0	 5.0	 30.0	 -30.0	 1.06	 100.0	 1	 1020	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0; % NG
	2	 29.5	 0.0	 90.0	 -90.0	 1.045	 100.0	 1	 177	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0; % NG
	3	 0.0	 20.0	 120.0	 -120.0	 1.01	 100.0	 1	 0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0; % SYNC
	6	 0.0	 9.0	 72.0	 -72.0	 1.07	 100.0	 1	 0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0; % SYNC
	8	 0.0	 9.0	 72.0	 -72.0	 1.09	 100.0	 1	 0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0; % SYNC
    15	 160	 2	     80	     -80	 1.01	 100.0	 1	 320	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0	 0.0; % Offshore Wind
];

%% generator cost data
%	2	startup	shutdown	n	c(n-1)	...	c0
%mpc.gencost = [
%	2	 0.0	 0.0	 3	   0.000000	  0.01	   0.000000; % NG
%	2	 0.0	 0.0	 3	   0.000000	  0.009	   0.000000; % NG
%	2	 0.0	 0.0	 3	   0.000000	   0.000000	   0.000000; % SYNC
%	2	 0.0	 0.0	 3	   0.000000	   0.000000	   0.000000; % SYNC
%	2	 0.0	 0.0	 3	   0.000000	   0.000000	   0.000000; % SYNC
%    2	 0.0	 0.0	 3	   0.000000	   0.002	   0.000000; % Offshore Wind
%];

mpc.gencost = [
	2	 0.0	 0.0	 3	   0.000000	  0.89	   0.000000; % NG
	2	 0.0	 0.0	 3	   0.000000	  0.889	   0.000000; % NG
	2	 0.0	 0.0	 3	   0.000000	  0.000000	   0.000000; % SYNC
	2	 0.0	 0.0	 3	   0.000000	  0.000000	   0.000000; % SYNC
	2	 0.0	 0.0	 3	   0.000000	  0.000000	   0.000000; % SYNC
    2	 0.0	 0.0	 3	   0.000000	  0.59   	   0.000000; % Offshore Wind
];

%% branch data
%	fbus	tbus	r	x	b	rateA	rateB	rateC	ratio	angle	status	angmin	angmax
mpc.branch = [
	1	 2	 0.01938	 0.05917	 0.0528	 472	 472	 472	 0.0	 0.0	 1	 -30.0	 30.0;
	1	 5	 0.05403	 0.22304	 0.0492	 500	 128	 128	 0.0	 0.0	 1	 -60.0	 60.0;
	2	 3	 0.04699	 0.19797	 0.0438	 500	 145	 145	 0.0	 0.0	 1	 -60.0	 60.0;
	2	 4	 0.05811	 0.17632	 0.034	 158	 158	 158	 0.0	 0.0	 1	 -30.0	 30.0;
	2	 5	 0.05695	 0.17388	 0.0346	 161	 161	 161	 0.0	 0.0	 1	 -30.0	 30.0;
	3	 4	 0.06701	 0.17103	 0.0128	 160	 160	 160	 0.0	 0.0	 1	 -30.0	 30.0;
	4	 5	 0.01335	 0.04211	 0.0	 664	 664	 664	 0.0	 0.0	 1	 -30.0	 30.0;
	4	 7	 0.0	 0.20912	 0.0	 141	 141	 141	 0.978	 0.0	 1	 -30.0	 30.0;
	4	 9	 0.0	 0.55618	 0.0	 53	 53	 53	 0.969	 0.0	 1	 -30.0	 30.0;
	5	 6	 0.0	 0.25202	 0.0	 117	 117	 117	 0.932	 0.0	 1	 -30.0	 30.0;
	6	 11	 0.09498	 0.1989	 0.0	 134	 134	 134	 0.0	 0.0	 1	 -30.0	 30.0;
	6	 12	 0.12291	 0.25581	 0.0	 104	 104	 104	 0.0	 0.0	 1	 -30.0	 30.0;
	6	 13	 0.06615	 0.13027	 0.0	 201	 201	 201	 0.0	 0.0	 1	 -30.0	 30.0;
	7	 8	 0.0	 0.17615	 0.0	 167	 167	 167	 0.0	 0.0	 1	 -30.0	 30.0;
	7	 9	 0.0	 0.11001	 0.0	 267	 267	 267	 0.0	 0.0	 1	 -30.0	 30.0;
	9	 10	 0.03181	 0.0845	 0.0	 325	 325	 325	 0.0	 0.0	 1	 -30.0	 30.0;
	9	 14	 0.12711	 0.27038	 0.0	 99	 99	 99	 0.0	 0.0	 1	 -30.0	 30.0;
	10	 11	 0.08205	 0.19207	 0.0	 141	 141	 141	 0.0	 0.0	 1	 -30.0	 30.0;
	12	 13	 0.22092	 0.19988	 0.0	 99	 99	 99	 0.0	 0.0	 1	 -30.0	 30.0;
	13	 14	 0.17093	 0.34802	 0.0	 76	 76	 76	 0.0	 0.0	 1	 -30.0	 30.0;
];
%% dc grid topology
%colunm_names% dcpoles
mpc.dcpol=2;
% numbers of poles (1=monopolar grid, 2=bipolar grid)
%% bus data
%column_names%   busdc_i grid    Pdc     Vdc     basekVdc    Vdcmax  Vdcmin Cdc corresponding_AC
mpc.busdc = [
    1              1       0       1       345         1.1     0.9     0 15;
    2              1       0       1       345         1.1     0.9     0 7;
];

%% converters
%column_names%   busdc_i busac_i type_dc type_ac P_g   Q_g  islcc  Vtar    rtf xtf  transformer tm   bf filter    rc      xc  reactor   basekVac    Vmmax   Vmmin   Imax    status   LossA LossB  LossCrec LossCinv  droop      Pdcset    Vdcset  dVdcset Pacmax Pacmin Qacmax Qacmin
mpc.convdc = [
    1       15   1       1       0       0    0 1     0.01  0.01 1 1 0.01 1 0.01   0.01 1  345         1.1     0.9     11     1       0 0  0    0      0.0050    -58.6274   1.0079   0 250 -250 100 -100;
    2       7   1       1       0       0    0 1     0.01  0.01 1 1 0.01 1 0.01   0.01 1  345         1.1     0.9     11     1       0 0  0    0      0.0070     21.9013   1.0000   0 250 -250 100 -100;
];
%% branches
%column_names%   fbusdc  tbusdc  r      l        c   rateA   rateB   rateC   status
mpc.branchdc = [
    1       2       0.052   0   0    250     250     250     1;
 ];

% INFO    : === Translation Options ===
% INFO    : Phase Angle Bound:           30.0 (deg.)
% INFO    : Line Capacity Model:         stat
% INFO    : Gen Active Capacity Model:   stat
% INFO    : Gen Reactive Capacity Model: am50ag
% INFO    : Gen Active Cost Model:       stat
% INFO    : Setting Flat Start
% INFO    : Line Capacity PAB:           15.0 (deg.)
% INFO    :
% INFO    : === Generator Classification Notes ===
% INFO    : SYNC   3   -     0.00
% INFO    : NG     2   -   100.00
% INFO    :
% INFO    : === Generator Active Capacity Stat Model Notes ===
% INFO    : Gen at bus 1 - NG	: Pg=232.4, Pmax=332.4 -> Pmax=340   samples: 20
% INFO    : Gen at bus 2 - NG	: Pg=40.0, Pmax=140.0 -> Pmax=59   samples: 6
% INFO    : Gen at bus 3 - SYNC	: Pg=0.0, Pmax=100.0 -> Pmax=0   samples: 0
% INFO    : Gen at bus 6 - SYNC	: Pg=0.0, Pmax=100.0 -> Pmax=0   samples: 0
% INFO    : Gen at bus 8 - SYNC	: Pg=0.0, Pmax=100.0 -> Pmax=0   samples: 0
% INFO    :
% INFO    : === Generator Reactive Capacity Atmost Max 50 Percent Active Model Notes ===
% INFO    : Gen at bus 2 - NG	: Pmax 59.0, Qmin -40.0, Qmax 50.0 -> Qmin -30.0, Qmax 30.0
% INFO    :
% INFO    : === Generator Active Cost Stat Model Notes ===
% INFO    : Updated Generator Cost: NG - 0.0 20.0 0.0430293 -> 0 22.8792990037 0
% INFO    : Updated Generator Cost: NG - 0.0 20.0 0.25 -> 0 36.3754226486 0
% INFO    : Updated Generator Cost: SYNC - 0.0 40.0 0.01 -> 0 0.0 0
% INFO    : Updated Generator Cost: SYNC - 0.0 40.0 0.01 -> 0 0.0 0
% INFO    : Updated Generator Cost: SYNC - 0.0 40.0 0.01 -> 0 0.0 0
% INFO    :
% INFO    : === Base KV Replacement Notes ===
% WARNING : Bus 1 : basekv changed 0.0 => 1.0
% WARNING : Bus 2 : basekv changed 0.0 => 1.0
% WARNING : Bus 3 : basekv changed 0.0 => 1.0
% WARNING : Bus 4 : basekv changed 0.0 => 1.0
% WARNING : Bus 5 : basekv changed 0.0 => 1.0
% WARNING : Bus 6 : basekv changed 0.0 => 1.0
% WARNING : Bus 7 : basekv changed 0.0 => 1.0
% WARNING : Bus 8 : basekv changed 0.0 => 1.0
% WARNING : Bus 9 : basekv changed 0.0 => 1.0
% WARNING : Bus 10 : basekv changed 0.0 => 1.0
% WARNING : Bus 11 : basekv changed 0.0 => 1.0
% WARNING : Bus 12 : basekv changed 0.0 => 1.0
% WARNING : Bus 13 : basekv changed 0.0 => 1.0
% WARNING : Bus 14 : basekv changed 0.0 => 1.0
% INFO    :
% INFO    : === Transformer Setting Replacement Notes ===
% INFO    :
% INFO    : === Line Capacity Stat Model Notes ===
% WARNING : Missing data for branch flow stat model on line 1-2 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.01938 x=0.05917
% INFO    : Updated Thermal Rating: on line 1-2 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 472
% WARNING : Missing data for branch flow stat model on line 1-5 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.05403 x=0.22304
% INFO    : Updated Thermal Rating: on line 1-5 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 128
% WARNING : Missing data for branch flow stat model on line 2-3 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.04699 x=0.19797
% INFO    : Updated Thermal Rating: on line 2-3 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 145
% WARNING : Missing data for branch flow stat model on line 2-4 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.05811 x=0.17632
% INFO    : Updated Thermal Rating: on line 2-4 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 158
% WARNING : Missing data for branch flow stat model on line 2-5 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.05695 x=0.17388
% INFO    : Updated Thermal Rating: on line 2-5 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 161
% WARNING : Missing data for branch flow stat model on line 3-4 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.06701 x=0.17103
% INFO    : Updated Thermal Rating: on line 3-4 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 160
% WARNING : Missing data for branch flow stat model on line 4-5 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.01335 x=0.04211
% INFO    : Updated Thermal Rating: on line 4-5 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 664
% WARNING : Missing data for branch flow stat model on line 4-7 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.0 x=0.20912
% INFO    : Updated Thermal Rating: on transformer 4-7 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 141
% WARNING : Missing data for branch flow stat model on line 4-9 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.0 x=0.55618
% INFO    : Updated Thermal Rating: on transformer 4-9 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 53
% WARNING : Missing data for branch flow stat model on line 5-6 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.0 x=0.25202
% INFO    : Updated Thermal Rating: on transformer 5-6 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 117
% WARNING : Missing data for branch flow stat model on line 6-11 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.09498 x=0.1989
% INFO    : Updated Thermal Rating: on line 6-11 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 134
% WARNING : Missing data for branch flow stat model on line 6-12 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.12291 x=0.25581
% INFO    : Updated Thermal Rating: on line 6-12 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 104
% WARNING : Missing data for branch flow stat model on line 6-13 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.06615 x=0.13027
% INFO    : Updated Thermal Rating: on line 6-13 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 201
% WARNING : Missing data for branch flow stat model on line 7-8 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.0 x=0.17615
% INFO    : Updated Thermal Rating: on line 7-8 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 167
% WARNING : Missing data for branch flow stat model on line 7-9 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.0 x=0.11001
% INFO    : Updated Thermal Rating: on line 7-9 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 267
% WARNING : Missing data for branch flow stat model on line 9-10 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.03181 x=0.0845
% INFO    : Updated Thermal Rating: on line 9-10 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 325
% WARNING : Missing data for branch flow stat model on line 9-14 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.12711 x=0.27038
% INFO    : Updated Thermal Rating: on line 9-14 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 99
% WARNING : Missing data for branch flow stat model on line 10-11 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.08205 x=0.19207
% INFO    : Updated Thermal Rating: on line 10-11 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 141
% WARNING : Missing data for branch flow stat model on line 12-13 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.22092 x=0.19988
% INFO    : Updated Thermal Rating: on line 12-13 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 99
% WARNING : Missing data for branch flow stat model on line 13-14 using max current model : from_basekv=1.0 to_basekv=1.0 r=0.17093 x=0.34802
% INFO    : Updated Thermal Rating: on line 13-14 : Rate A, Rate B, Rate C , 9900.0, 0.0, 0.0 -> 76
% INFO    :
% INFO    : === Voltage Setpoint Replacement Notes ===
% INFO    : Bus 1	: V=1.06, theta=0.0 -> V=1.0, theta=0.0
% INFO    : Bus 2	: V=1.045, theta=-4.98 -> V=1.0, theta=0.0
% INFO    : Bus 3	: V=1.01, theta=-12.72 -> V=1.0, theta=0.0
% INFO    : Bus 4	: V=1.019, theta=-10.33 -> V=1.0, theta=0.0
% INFO    : Bus 5	: V=1.02, theta=-8.78 -> V=1.0, theta=0.0
% INFO    : Bus 6	: V=1.07, theta=-14.22 -> V=1.0, theta=0.0
% INFO    : Bus 7	: V=1.062, theta=-13.37 -> V=1.0, theta=0.0
% INFO    : Bus 8	: V=1.09, theta=-13.36 -> V=1.0, theta=0.0
% INFO    : Bus 9	: V=1.056, theta=-14.94 -> V=1.0, theta=0.0
% INFO    : Bus 10	: V=1.051, theta=-15.1 -> V=1.0, theta=0.0
% INFO    : Bus 11	: V=1.057, theta=-14.79 -> V=1.0, theta=0.0
% INFO    : Bus 12	: V=1.055, theta=-15.07 -> V=1.0, theta=0.0
% INFO    : Bus 13	: V=1.05, theta=-15.16 -> V=1.0, theta=0.0
% INFO    : Bus 14	: V=1.036, theta=-16.04 -> V=1.0, theta=0.0
% INFO    :
% INFO    : === Generator Setpoint Replacement Notes ===
% INFO    : Gen at bus 1	: Pg=232.4, Qg=-16.9 -> Pg=170.0, Qg=5.0
% INFO    : Gen at bus 2	: Pg=40.0, Qg=42.4 -> Pg=29.5, Qg=0.0
% INFO    : Gen at bus 3	: Pg=0.0, Qg=23.4 -> Pg=0.0, Qg=20.0
% INFO    : Gen at bus 6	: Pg=0.0, Qg=12.2 -> Pg=0.0, Qg=9.0
% INFO    : Gen at bus 8	: Pg=0.0, Qg=17.4 -> Pg=0.0, Qg=9.0
% INFO    :
% INFO    : === Writing Matpower Case File Notes ===

