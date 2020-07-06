%--------------------------------------------------------------------------
%------------------Radial Turbine Design Tool------------------------------
%--------------------------------------------------------------------------
% written by Lukas Badum, contact l.badum@web.de
% For a detailed documentation, see word document "radial turbine design
% documentation"
% This design tool calculates the rotor velocity triangles, inlet and
% outlet blade height, inlet and outlet radii and axial length of a radial
% turbine. Additionally, the stator outlet radius, stator blade number and
% outlet flow angle are determined.

% If necessary, a specific or total heat flux for turbine stator and rotor
% can be specified and will be additionally adressed in the design process
% (diabatic turbine design).

% Total to static isentropic efficiency is estimated based on
% the following loss mechanisms:
% -	Incidence losses (incidence tangential kinetic energy is lost)
% -	Secondary flow losses (fluid not following the main flow path)
% -	Skin friction losses (rough walls)
% -	Tip clearance losses (reduced energy conversion)
% -	Exit energy loss (kinetic energy in exhaust gas)
clear;
close all;
%INPUT PARAMETERS
%#thermodynamics:
m_dt = 0.006;  % mass flow rate m [kg/s]
Q_46 = 000;        %heat input [W]
TIT = 1200;     % Stator inlet Temperature TIT [K]
P_1t = 2.5e5;   % Stator total inlet pressure P_1t [Pa]
P_amb = 1.013e5;      % rotor static outlet pressure
q_13 = 0;        % heat flux stator q_s [J/kg]
q_46 = Q_46/m_dt;        % Heat flux rotor q_r  [J/kg]
f = 0.01;        % fuel to air ratio [];
xi_s = 0.98;   % Nozzle total pressure loss factor stator according to Wasserbauer, Glassman, "FORTRAN PROGRAM FOR PREDICTING OFF-DESIGN PERFORMANCE OF RADIAL-INFLOW TURBINES", p.3
y_plus = 1;    %CFD y plus wall spacing calculation
%mean dynamic viscosity:
mu_4 = 48e-6;                           %dynamic viscosity approximation inlet [Pa s]
mu_6 = 43e-6;                           %dynamic viscosity approximation outlet [Pa s]
mu_m = (mu_4+mu_6)/2;
%calculate thermodynamic properties based on stator total inlet
%temperature:
[gamma,cp,R] = thermo_properties(f,TIT);

%loss model selection:
lossmodel = 2;
%#1 - Moustapha         0.33*(W_41^2+W_6s^2)/2;
%#2 - Wasserbauer       0.3*(W_4^2*cos(i_4)^2+W_6^2)/2;
%#3 - CETI              K_p*(L_h_ceti/D_h_ceti+0.68*(1-((r_6s-r_6h)/(2*r_4))^2)*cos(abs(beta_6m))/(b_6/C))*(W_4^2+W_6^2)/2
%#4 - Balje
%#5 - Rodgers
%radial or mixed flow turbine?
design = 'radial'; %'radial' or 'mixed'

%#geometry:
e_ax = 0.2e-3;     % tip clearance axial [m]
e_rad = 0.2e-3;    % tip clearance radial [m]
e = (e_ax+e_rad)/2; %mean tip clearance [m]
k = 0.3e-3;          % absolute surface roughness k [m]
k_bl = 0.98;    %boundary layer blockage parameter
beta_4b = 40/180*pi;    % blade angle at inlet #!!! must be positive!
if beta_4b<0
    error('inlet blade angle is negative!')
end

%#stage design parameters:
rpm = 500000;   % maximum rotational speed rpm_max  [1/min]
omega=rpm/60*2*pi;
Xi = 0.7;         % rotor inlet/outlet meridional velocity ratio
tb_r = 0.3e-3;          % rotor blade thickness t_b [m] (uniform)
r_fbr = 0.1e-3;         %rotor blade root fillet radius


%CONSTRAINTS
beta_6m_max=-50/180*pi;     % outlet maximum blade angle [�]
sigma_y=700;        % yield stress sigma_y  [MPa]
r_6hmin = 1.5e-3;     % minimum hub outlet radius r_6h_min [m]
%maximum radius ratio r6s/r4 -> it is important to constrain to keep
%curvature low:
%"This parameter is directly linked to the curvature of the rotor shroud
%contour in the meridional plane. In particular is often suggested that
%light curvature can lead to higher efficiency; a typical value suggested
%is r6s/r4=0.7" from "A mean-line model to predict the design
            %performance of radial inflow turbines in Organic Rankine
            %Cycles." (2014)., p. 77, with reference to  Moustapha, Hany,
            %et al. "Axial and radial turbines"
epsilon_max = 0.85;  % maximum radius ratio r6s/r4
maximum_iterations = 100;    %maximum design iterations before continuation



%Notation:
% 1 = STATOR inlet, downstream of IGV
% 3 = STATOR outlet, diffuser inlet
% 4 = ROTOR INLET
% 6 = ROTOR OUTLET
vPsi = linspace(0.4,1.5,20);
vPhi = linspace(0.1,0.5,20);
vPsi = 1.2;
vPhi = 0.4;
%         

for i=1:length(vPsi)
    Psi = vPsi(i);
    for j=1:length(vPhi)
        Phi = vPhi(j);
        eta_error=100;
        iteration_index = 1;
        valid_design=1; %assumption that design is valid
        C_u6m=0;
        flag_beta6m=0;
        
        %INITIAL CONDITIONS
        M_4 = 0.7;          % Rotor inlet Mach number
        M_6 = 0.3;          % Rotor outlet Mach number
        C_u6m = 0;           % tangential outlet velocity mid-span
        C_u6s = 0;           % tangential outlet velocity shroud
        C_u6h = 0;           % tangential outlet velocity hub
        eta_pts = 0.7;        % polytropic efficiency
        b_4 = 0.001;        %blade height rotor inlet [m]
        b_6 = b_4*3;
        alpha_4 = 75/180*pi;    %rotor inlet total flow angle
        r_4 = 0.01;         %rotor inlet radius [m]
        epsilon = epsilon_max; % initial radius ratio r6s/r4
        r_6s = r_4*epsilon;
        r_6h = r_6hmin;
        C_6 = 0;
        Z_r =10;        %number of blades
        whilelimit = 20;    %while loop iteration limit
        flag_beta6m=0;
        P_6 = P_amb;
        eta_pts_old = eta_pts;   
        r_4_old = r_4;
        beta_6m_old = 0;
        while(abs(eta_error)>0.00001)
%--------------------------------------------------------------------------
%-----------------------Thermodynamic Calculations-------------------------
%--------------------------------------------------------------------------
%######################## STATOR ##########################################          
            %radius nozzle trailing edge according to Watanabe, "Effect of Dimensional Parameters
            % of Impellers on Performance Characteristics of a Radial Inflow Turbine
            r_3 = 2*b_4*cos(alpha_4)+r_4;

            %radius of nozzle leading edge according to Glassman, �Computer Program for Design Analysis of Radial-
            %Inflow Turbines�:
            r_1 = r_3*1.25;            
           
            %stator chord length approximation by assuming total outlet flow angle
            %= balde angle:
            %start point of guide vane camber line: find cross section of line with
            %slope of alpha_4 and intersection of r_3:
            [xout,yout] = linecirc(real(tan(pi/2-alpha_4)),real(abs(r_3)),0,0,real(abs(r_1)));
            %start point of guide vane camber line on outer stator radius:
            P_gv_start = [xout(2);yout(2)];
            %end point of guide vane camber line on innter stator radius:
            P_gv_end = [0;r_3];
            %chord length:
            c_s = sqrt(sum(P_gv_start-P_gv_end).^2);
            %number of stator blades according to Simpson, A., Spence, S., and Watterson, J., 2008, �Numerical and Experimental
            %Study of the Performance Effects of Varying Vaneless Space and Vane Solidity
            %in Radial Inflow Turbine Stators�
            alpha_4/pi*180;
            Z_s = ceil((2*pi*r_1*1.25)/c_s);
            %solidity:
            s_s = 2*pi*r_3/Z_s;
            %throat o_s:
            o_s = s_s*cos(alpha_4);
            %effective flow area:
            A_3_eff = o_s*b_4*(Z_s-1);
            %pitch chord ratio:
            s_c_ratio = s_s/c_s;     
            
            %total inlet temperature is T_1t:
            T_1t = TIT;
            %stator outlet total temperature and pressure:
            T_3t = TIT-q_13/cp;
            %total outlet pressure based on total pressure loss coefficient
            %as reported by Wasserbauer, Glassmann, "FORTRAN PROGRAM FOR
            %PREDICTING OFF-DESIGN PERFORMANCE OF RADIAL-INFLOW TURBINES":
            P_3t = P_1t*0.967;
            %while loop to determine nozzle outlet mach number:
            M_3old = M_4;
            M_3 = M_4;
            Merror = 1;
            if iteration_index==1
                P_3 = P_3t*(1+(gamma-1)/2*M_3^2)^(-gamma/(gamma-1));
                T_3 = T_3t*(1+(gamma-1)/2*M_3^2)^(-1);
            else            
                while Merror >0.01
                    P_3 = P_3t*(1+(gamma-1)/2*M_3^2)^(-gamma/(gamma-1));
                    T_3 = T_3t*(1+(gamma-1)/2*M_3^2)^(-1);
                    rho_3 = P_3/(R*T_3);
                    C_3 = m_dt/(rho_3*A_3_eff);
                    M_3 = C_3/sqrt(gamma*R*T_3);
                    Merror = abs(M_3-M_3old);
                    M_3old = M_3;
                end
            end
            
            %Rotor
            %inlet total conditions:
            T_4t = T_3t;
            P_4t = P_3t;
            %inlet static conditions:
            P_4 = P_4t*(1+(gamma-1)/2*M_4^2)^(-gamma/(gamma-1));
            T_4 = T_4t*(1+(gamma-1)/2*M_4^2)^-1;
            %resulting inlet velocity:
            C_4 = M_4*sqrt(gamma*R*T_4);
            %pressure changing work - initial condition:
            m = gamma/((gamma-1)*eta_pts);
            pi_46 = P_6/P_4;
            %in the first iteration, assume work output of ideal reference
            %process according to specified initial polytropic efficiency
            %(initially, diabatic effect is not considered):
            if iteration_index ==1
                y_46 = polytropic_work(m,T_4,pi_46,R);
                %resulting losses - initial condition:
                j_46 = y_46*(eta_pts-1);
                j_46_old = j_46;
            else %if the first iteration is passed already
                %calculation of ideal polytropic reference process work:
                
                y_error = 10;
                pi_46 = P_6/P_4;
                sum1 = 0;
                while y_error > 1&sum1<whilelimit   %maximum specific work output error: 1J/kg
                    y_46_old = y_46;                    
                    %polytropic ratio for diabatic process:
                    nu = 1+(q_46+j_46)/y_46_old;
                    m = gamma/((gamma-1)*nu);
                    y_46 = polytropic_work(m,T_4,pi_46,R);
                    y_error = abs(y_46_old-y_46);
                    sum1 = sum1+1;
                end
                sum1 = 0;
            end
%             nu
            %iterative calculation of outlet conditions:
            c_error = 10;
            sum1=0;
            while c_error>1 %maximum velocity error 1 m/s
                C_6_old = C_6;
                T_6t = T_4t + (q_46 + j_46+y_46+0.5*(C_6^2-C_4^2))/cp;
                T_6s = T_4t + (y_46-0.5*C_4^2)/cp;
                T_6 = T_6t*(1+(gamma-1)/2*M_6^2)^-1;
                C_6 = M_6*sqrt(gamma*R*T_6);
                c_error = abs(C_6-C_6_old);
                sum1 = sum1+1;
                    if sum1>whilelimit
                        sum1=0;
                        break;
                    end
            end
            %total outlet pressure:
            P_6t = P_6*(1+(gamma-1)/2*M_6^2)^(gamma/(gamma-1));
            rho_6 = P_6/(R*T_6);
            %useful work of the turbine:
            w_t46q = y_46+j_46+0.5*(C_6^2-C_4^2);

            %calculate thermodynamic properties based on stator total inlet
            %temperature:
            [gamma_4,cp_4,R] = thermo_properties(f,T_4);
            [gamma_6,cp_6,R] = thermo_properties(f,T_6);
            mu_4 = mu_of_t(T_4);
            mu_6 = mu_of_t(T_6);
            mu_m = (mu_4+mu_6)/2;
            gamma = (gamma_4+gamma_6)/2;
            cp = (cp_4+cp_6)/2;
       
            
            %isentropic comparison process (only valid for adiabatic
            %analysis) from total to static
            T_6s = T_1t*(P_6/P_1t)^((gamma-1)/gamma);
            T_6ts = T_1t*(P_6t/P_1t)^((gamma-1)/gamma);
            dh_46sts = cp*(T_1t-T_6s);
            dh_46stt = cp*(T_1t-T_6ts);
%--------------------------------------------------------------------------
%-----------------------Stage Design---------------------------------------
%--------------------------------------------------------------------------
%######################## ROTOR ###########################################
            %circumferential velocity at inlet from head coefficient:
            U_4 = sqrt(-w_t46q/Psi);
            if w_t46q>0||not(isreal(U_4))
            disp(['Error: Positive work output at Psi = ' num2str(Psi) ' Phi = ' num2str(Phi)]);
            break;
            end
            r_4=U_4/omega;
            
            %shroud radius at outlet from radius ratio:
            r_6s = r_4*epsilon;
            %meridional inlet velocity from flow coefficient and meridional velocity
            %ratio:
            C_m4 = Phi*U_4*Xi;
            %meridional outlet velocity from flow coefficient:
            C_m6m = Phi*U_4;
            %mid-span radius r_6m is average between outer radius and
            %minimum radius:
            r_6rms = sqrt((r_6s^2+r_6h^2)/2);
            %tangential velocity at inlet:
            C_u4 = Psi*U_4+r_6rms/r_4*C_u6m;
            %resulting relative inlet flow angle:
            beta_4 = sign(C_u4-U_4)*atan(abs(C_u4-U_4)/C_m4);
            %total inlet angle:
            alpha_4 = atan(C_u4/C_m4);
            %inlet conditions:
            C_4 = sqrt(C_m4^2+C_u4^2);
            M_4 = C_4/(sqrt(gamma*R*T_4));

            %inlet static conditions:
            P_4 = P_4t*(1+(gamma-1)/2*M_4^2)^(-gamma/(gamma-1));
            T_4 = T_4t*(1+(gamma-1)/2*M_4^2)^-1;
            rho_4 = P_4/(R*T_4);
            rho_4t = P_4t/(R*T_4t);
            %calculation of inlet blade height:
            b_4 = m_dt/(rho_4*C_m4*(2*pi*r_4*k_bl-Z_r*tb_r));
            
            %relative tip clearance:
            e_rel = e/b_4;
            %relative inlet conditions:
            W_m4 = C_m4;
            W_u4 = W_m4*tan(beta_4);
            W_4 = sqrt(W_u4^2+C_m4^2);
            M_4rel = W_4/sqrt(gamma*R*T_4);
            T_4trel = T_4+W_4^2/(2*cp);
            P_4trel = P_4*(T_4trel/T_4)^(gamma/(gamma-1));
            
            
            %iteration for outlet area of the turbine, assuming
            %constant meridional velocity over span:
            A_6 = m_dt/(rho_6*C_m6m*k_bl);
%             A_6 = m_dt/(rho_6*C_m6m*k_bl)+Z_r*tb_r*b_6/k_bl;
            %calculate outer diameter according to specified minimum
            %hub diameter:
            %hub radius: set to 0.3*r_4, but if radius is smaller than
            %minimum radius, set to r_6hmin which is specified
            r_6h = max(r_6hmin,0.3*r_4);
            r_6s =  sqrt(r_6h^2+A_6/pi);
            
            epsilon = r_6s/r_4;
            if epsilon<=epsilon_max
                valid_design=1;
            else
                valid_design=0;
                disp('inlet to outlet radius ratio exceeded!')
                break;
            end
            
            %relative meridional velocities at outlet: assuming
            %constant meridional velocity
            W_m6m = C_m6m;
            W_m6s = C_m6m;
            W_m6h = C_m6m;
            
            %mid-span radius at outlet:
            r_6rms = sqrt((r_6s^2+r_6h^2)/2);
            %root mean square radius ratio:
            epsilon_rms = r_6rms/r_4;
            %blade height at outlet:
            b_6 = r_6s-r_6h;
            %circumferential velocity at outlet mid-span:
            U_6m = omega*r_6rms;
            %circumferential velocity at outlet hub:
            U_6h = omega*r_6h;
            %circumferential velocity at outlet shroud:
            U_6s = omega*r_6s;
            %outlet velocities (total):
            C_6 = sqrt(C_m6m^2+C_u6m^2);
            M_6 = C_6/(sqrt(gamma*R*T_6));
            
            %calculating beta angles:
            beta_6m = sign(C_u6m-U_6m)*atan((U_6m-C_u6m)/W_m6m);
            beta_6s = sign(C_u6s-U_6s)*atan((U_6s-C_u6s)/W_m6s);
            beta_6h = sign(C_u6h-U_6h)*atan((U_6h-C_u6h)/W_m6h);
            
            %number of blades according to Ventura:
            Z_r = round( (pi*(110/180*pi-alpha_4)*tan(alpha_4))/(30/180*pi));
            %solidity:
            
            %maximum number of blades according to blade thickness and
            %outlet radius:
            tb_90 = (tb_r+2*r_fbr)/cos(beta_6m);
            Z_r_max = ceil(2*pi*r_6h/(tb_90));
            Z_r = min(Z_r_max,Z_r);
            
            %solidity at root mean radius:
            s_6 = 2*pi*r_6rms/Z_r;
            %throat approximation assuming that blade angle is flow angle:
            o_6 = s_6*cos(beta_6m)-tb_r;
            
            %relative conditions at rotor outlet at mid-span, shroud
            %and hub:
            W_u6m = C_m6m*tan(beta_6m);
            W_6rms = sqrt(W_u6m^2+C_m6m^2);
            W_u6s = C_m6m*tan(beta_6s);
            W_6s = sqrt(W_u6s^2+W_m6s^2);
            W_u6h = C_m6m*tan(beta_6h);
            W_6h = sqrt(W_u6h^2+W_m6h^2);
            %assuming root mean square velocity as outlet velocity:
            W_6 = W_6rms;
            
            M_6rel = W_6/sqrt(gamma*R*T_6);
            T_6trel = T_6+W_6^2/(2*cp);
            P_6trel = P_6*(T_6trel/T_6)^(gamma/(gamma-1));
            
            %_____________________________________________________________
            %if blade angle exceeds maximum blade angle, set new flow angle
            %according to maximum flow angle:            
            if abs(beta_6m)>abs(beta_6m_max)||flag_beta6m==1
                %set blade and flow angle at outlet to maximum blade angle
                %specified:
                beta_6m = beta_6m_max;
                %calculate new tangential velocity at rms radius at outlet
                %according to maximum blade angle:
                W_u6m = tan(beta_6m)*C_m6m;
                %calculate hub and shroud relative tantential velocities
                %according to radius ratios
                W_u6s = r_6s/r_6rms*W_u6m;
                W_u6h = r_6h/r_6rms*W_u6m;
                %set 
                C_u6s = W_u6s+U_6s;
                C_u6h = W_u6h+U_6h;
                C_u6m = W_u6m+U_6m;
                flag_beta6m = 1;
            end

            
%             %conduct bisection method to find blade angle at mid-span:
%             beta_6ms=pi/2-abs(beta_6m); %convert to angle convention used by Suhrmann
%             f_beta_6b = @(beta_6b) (1+((m_dt*sqrt(R*TIT)/(P_6*4*r_4^2*(2*tan(beta_6b)-0.5)))^(0.02*beta_6b-0.255))*3*pi/Z_r+7.85*e_rel)*beta_6b-beta_6ms;
%             %guess for lower and upper limit of the blade angle:
%             a = pi/2;
%             b = 0;
%             beta_6bm = f_bisection(f_beta_6b,a,b,1/180*pi);
%             beta_ratio_suhrmann = beta_6ms/beta_6bm;
%             beta_6bm = sign(beta_6m)*(pi/2-beta_6bm);

            %total flow angle outlet:
            alpha_6m = atan(C_u6m/C_m6m);
            alpha_6s = atan(C_u6s/C_m6m);
            alpha_6h = atan(C_u6h/C_m6m);
           
%######################## Diffuser ########################################
            %area ratio:
            AR = 2.4;
            %diffuser outlet area:
            A_7 = A_6*AR;
            %ideal recovery factor:
            Cpi = 1-1/AR^2;
            %real recovery factor accoridng to Japikse, D., and R. Pampreen. "Annular diffuser performance for an automotive gas turbine." (1979): 358-372.
            Cp = 0.6;
            %dynamic pressure at P_6:
            P_6dyn = P_6t-P_6;
            P_7 = P_amb;
            P_6_new = P_7-Cp*P_6dyn;
            %initial conditions for outlet pressure calcualtion:
            Merror = 10;
            M_7 = M_6;
            M_7old = M_7;
            %iterative calculation of diffuser exit conditions:
                 while Merror >0.01
                    T_7 = T_6t*(1+(gamma-1)/2*M_7^2)^(-1);
                    rho_7 = P_7/(R*T_7);
                    C_7 = m_dt/(rho_7*A_7);
                    M_7 = C_7/sqrt(gamma*R*T_7);
                    Merror = abs(M_7-M_7old);
                    M_7old = M_7;
                end
%--------------------------------------------------------------------------
%---------------------------Geometry Generation----------------------------
%--------------------------------------------------------------------------
            
            %axial length correlation according to Aungier, R.H.
            % Turbine Aerodynamics: Axial-Flow and Radial-Flow Turbine
            %Design and Analysis
            %             z_r = (r_6s-r_6h)*1.5;
            %alternative formulation by aungier:
            % R.H. Aungier,Centrifugal Compressors A Strategy for Aerodynamic Design andAnalysis, ASME 2000
            z_r = 2*r_6s*(0.014+0.023*r_4/r_6h+1.58*Phi);
            
            %%%% Calculation of hub and shroud geometry and mean blade
            %%%% surface length
            %             %Bezier spline parameter from 0 to 1
            u = linspace(0,1,20);
            %hub contour:
            P0 = [0;r_6h]; P1 = [0;r_6h]; P2 = [0.5*z_r;r_6h]; P3 = [z_r;r_6h+(r_4-r_6h)/3]; P4 = [z_r;r_6h+2*(r_4-r_6h)/3]; P5 = [z_r;r_4]; P6 = [z_r;r_4*1.2];
            Phub = [P0 P1 P2 P3 P4 P5]; Phub = flip(Phub,2);

            %hub contour points at Bezier spline parameter u:
            [Rhub] = bezier_spline(Phub,u);

            %shroud contour:
            P0 = [0;r_6s]; P1 = [0.5*(z_r-b_4);r_6s]; P2 = [0.75*(z_r-b_4);r_6s+((r_4-r_6s)/3)/2]; P3 = [z_r-b_4;r_6s+2*(r_4-r_6s)/3]; P4 = [z_r-b_4;r_4];
            Pshroud = [P0 P1 P2 P3 P4];Pshroud = flip(Pshroud,2);
            [Rshroud] = bezier_spline(Pshroud,u);
            
            %meanline meridional points in z-r plane:
            R_ml =  (Rhub+Rshroud)/2; P_ml = R_ml;
            %assume linear blade beta angle change from inlet to outlet:
            beta_ml = linspace(beta_4b, beta_6m, length(u));
            %calculate euclidian distance of the interpolation points in
            %z-r plane:
            dm = (diff(R_ml'))';dm = dm.^2;dm = sum(dm);dm = sqrt(dm);
            %meridional length at every point:
            L_m = cumsum([0 dm]);
            L_ms = L_m(end);
            
            
            %alternative formulation of mean surface length:
            %mean surface length according to Ventura et al.
%             L_ms_ceti=pi/2*sqrt(0.5*((r_4-r_6s+b_4/2)^2+(b_6/2)^2));
            L_ms_ceti = pi/4 * ((z_r-b_4/2+(r_4-r_6s-b_6/2)));
            %blade solidity:
            s = L_ms*Z_r/(2*r_4);
            %alternative mean curvature radius calculation:
            r_c = z_r/(2*sin(0.5*(pi/2-beta_6m)));
            

            
%--------------------------------------------------------------------------
%-----------------------Losses---------------------------------------------
%--------------------------------------------------------------------------
%loss model combination were selected based on recommendation of
%Persky, Rodney, and Emilie Sauret. "Loss models for on and off-design
%performance of radial inflow turbomachinery." Applied Thermal Engineering
%150 (2019): 1066-1077.  
%###############################Nozzle Losses##############################
            %Rodgers, C. "Efficiency and performance characteristics of
            %radial turbines." SAE Transactions (1967): 681-692. 
            Re_nozzle = C_4*b_4*rho_4/mu_4;
            xi_n=0.05/Re_nozzle^(1/5)*(3*cos(pi/2-alpha_4)/s_c_ratio+s_s*sin(pi/2-alpha_4)/b_4);
            dh_nozzle = xi_n*C_4^2/2;
            Y_N = xi_n*(1+0.5*gamma*M_3^2);
            P_3t = (P_1t+Y_N*P_3)/(1+Y_N);
            xi_s = P_3t/P_1t;

%########################## Incidence Losses ##############################
            %Incidence Loss Model:

            %Incidence Loss Model #2: assuming that part of the incidence
            %kinetic energy is recovered based on the relative eddy inside
            %the passage and the resulting optimum incidence angle, see Wasserbauer C.A., Glassman A.J. - FORTRAN program for predicting the off-design performance of radial-inflow turbines, NASA TN 8063, 1975
            %Incidence Loss Model #2.1
            %optimum incidence angle according to
            %Stanitz J.D. � "Some theoretical aerodynamic investigations of impellers in radial and mixed flow centrifugal compressors", trans. ASME, 1952, 74: 473
            beta_4opt_stanitz = atan(-1.98*tan(alpha_4)/(Z_r*(1-(1.98/Z_r))))+beta_4b;
            
            %incidence angle relative to optimum incidence angle (see
            %Wasserbauer, Charles A., and Arthur J. Glassman. "FORTRAN
            %program for predicting off-design performance of radial-inflow
            %turbines." (1975). p.4:
            beta_4opt = beta_4opt_stanitz;
            i_4 = beta_4-beta_4opt;
            %according to Persky, Rodney, and Emilie Sauret. "Loss models
            %for on and off-design performance of radial inflow
            %turbomachinery." Applied Thermal Engineering 150 (2019):
            %1066-1077., n should be chosen to be 2!   
            n = 2;
            dh_til = 0.5*W_4^2.*sin(abs(i_4)).^n;
           
% %########################## Friction Losses #########################
            %hydraulic length:
            L_h = L_ms;
            L_h_ceti = L_ms_ceti;
%             %hydraulic diameter - average inlet and outlet:
            D_h = 0.5*((4*pi*r_4*b_4/(2*pi*r_4+Z_r*b_4)+(2*pi*(r_6s^2-r_6h^2)/(pi*(r_6s-r_6h)+Z_r*b_6))));
            D_h_ceti = D_h;
%             %mean relative velocity:
%             W_m = (W_4+(W_6s+W_6h)/2)/2;
% 
%             %Reynolds number in relative system:
%             Re_W = W_m * D_h / (mu_m/((rho_6+rho_4)/2));
%             %friction factor calculation #1
%             %function of fanning friction factor for according to Ventura:
%             f_cf = @(cf) -4*log10(k/(3.7*D_h)+1.256/(Re_W*sqrt(cf)))-1/sqrt(cf);
%             a = 0;
%             b = 1;
%             r = 0.0001;
%             c_f = f_bisection(f_cf,a,b,r);
% 
%             %losses of bent pipe:
%             c_fc = c_f*(1+0.075*Re_W^0.25*sqrt(D_h/(2*r_c)));
%             %modified losses in turbomachinery passages:
%             c_fct = c_fc*(Re_W*(r_4/r_c)^2)^0.05;
%             dh_tf=c_fct*L_h/D_h*W_m^2;
                        dh_tf = 0;
%########################## Passage Losses ####################
% %Reynoldsnumber dependency:
% %cord length:
c_r = sqrt((r_4-r_6h+b_4/2)^2+(z_r)^2);
Re_ref = 20e5;
%as proposed by Wasserbauer et al.:
lc_ref = 0.3+(1-0.3)*Re_ref^-0.2;   %reference loss coefficient
Re_passage = W_6 * c_r * rho_6/ mu_6;
K = 0.3;
lc_passage = K+(1-K)*Re_passage^-0.2;
Re_loss_ratio = lc_passage/lc_ref;

            if lossmodel == 1
                %#loss correlation 1:
                %##########################################################
                %formulation according to
                %Moustapha, Hany, et al. "Axial and radial turbines.
                %Concepts ETI." Inc., Wilder, VT (2003). cited by Paltrinieri, Andrea. "A mean-line model to predict the design performance of radial inflow turbines in Organic Rankine Cycles." (2014).
                %shroud relative velocity:
                K = 0.33;
                dh_tsf_mo = K*(W_41^2+W_6^2)/2;
                dh_tsf = dh_tsf_mo;
            end
            
            if lossmodel == 2
                %#loss correlation 2:
                %##########################################################
                %Wasserbauer, Charles A., and Arthur J. Glassman. "FORTRAN
                %program for predicting off-design performance of radial-inflow
                %turbines." (1975). p.4:
                sigma = 1-sqrt(pi/2-beta_4b)/(Z_r^0.7);
                C_u4opt = U_4*sigma;
                beta_4opt_test = atan((C_u4opt-U_4)/C_m4);
                i_4 = beta_4-beta_4opt;
                
                K = 0.3;
                dh_tsf_wb = 1/2*K*(W_4^2*cos(i_4)^2+W_6^2);
                dh_tf = 0;
                dh_tsf = dh_tsf_wb;
            end
            
            %#loss correlation 3: CETI passage loss model
            %##############################################################
            if lossmodel == 3
                if (r_4-r_6s)/b_6>0.2
                    K_p = 0.11;
                else
                    K_p = 0.22;
                end
                beta_mean = atan(0.5*(tan(abs(beta_4))+tan(abs(beta_6m))));
                C = z_r/cos(abs(beta_mean));
                %modifications/uncertainties: r_6rms instead for r, W_6s instead of W_6
                dh_tsf_CETI = K_p*(L_h/D_h+0.68*(1-(r_6rms/r_4)^2)*cos(abs(beta_mean))/(b_6/C))*(W_4^2+W_6rms^2)/2;
                dh_tf = 0;
                dh_tsf = dh_tsf_CETI;
            end
            
            %#loss correlation 4: Balje passage loss model
            %##############################################################
            if lossmodel == 4
                if (r_4-r_6s)/b_6>0.2
                    K_p = 0.11;
                else
                    K_p = 0.22;
                end
                Phi_in = C_m4/U_4;
                K_I = C_m4/C_m6m;
                Xi_I = 0.88-0.5*Phi_in;
                dh_tsf_balje = Phi_in^1.75*(1+K_I)^2/8*Xi_I*U_4^2;
%                 dh_tf = 0;
                dh_tsf = dh_tsf_balje;
            end
            
            if lossmodel == 5
            %loss correlation 5: Rodgers, C. "Efficiency and performance
            %characteristics of radial turbines." SAE Transactions (1967): 681-692. 
            lambda_th = dh_46sts/U_4^2;
            dh_blading_rodgers = (1.2*s_c_ratio-W_mR/U_4*1/lambda_th)*W_mR^2;
            dh_secondary_rodgers = W_mR^2*(0.01*2*r_4/b_4*s_c_ratio+(1-cos(alpha_6)));
            dh_tsf = dh_blading_rodgers+dh_secondary_rodgers;
            dh_tsf = C_u4*U_4*2*r_4/(Z_r*L_h);
            end
            %Reynolds number correction of passage losses:
            dh_tsf = dh_tsf*Re_loss_ratio;
%########################## Tip Clearance Losses ####################
            %loss correlation according to Rodgers
            %"Performance of High-Efficiency Radial/Axial Turbine"
            dh_ttc = 0.4*C_u4^2*e/b_4;    
            
            %loss correlation according to Baines
            %"Axial and Radial Turbines Part 3: Radial Turbine Design"
            K_a = 0.4; K_r = 0.75; K_ar = -0.3;
            C_a = (1-r_6s/r_4)/(C_m4*b_4);
            C_r = (r_6s/r_4)*(z_r-b_4)/(C_m6m*r_6rms*b_6);
            dh_ttc = real(U_4^3*Z_r/(8*pi)*(K_a*e_ax*C_a+K_r*e_rad*C_r+K_ar*sqrt(e_ax*e_rad*C_a*C_r)));
            
            if lossmodel == 5
            %Rodgers, C. "Efficiency and performance characteristics of
            %radial turbines." SAE Transactions (1967): 681-692. 
            lambda_th = dh_46sts/U_4^2;
            dh_ttc = U_4^2*(2*r_4+2*r_6s)/(2*r_4+2*r_6h)*(1-(pi*b_4/(8*L_h)))*3.5*e*lambda_th/(b_4+b_6);
            end
            
%########################## Trailing Edge Losses ####################
            %according to Glassman, �Enhanced Analysis and User�s Manual for Radial-
            %Inflow Turbine Conceptual Design Code RTD,� -was found to be
            %errorous for high blade angles!!!!
            delta_P_t_rel = rho_6*W_6rms^2/2*(Z_r*tb_r/(pi*(r_6s+r_6h)*cos(beta_6m)))^2;
            dh_te = 2/(gamma*M_6rel^2)*delta_P_t_rel/(P_6*(1+W_6rms^2/(2*T_6*cp))^(gamma/(gamma-1)));
%Baines Correlation:
%             dh_te = 0.5*C_6^2*0.2*tb_r/o_6;
%########################## Kinetic Energy Exit Losses ####################
            dh_tke = (1-Cp)*C_6^2/2;
            
%########################## Windage Losses ####################
%                             kf_low = 3.7*(e_b/r_4)^0.1/(Re^(1/2));
%                             kf_high = 0.102*(e_b/r_4)^0.1/Re^(1/5);
%                             kf = Re(Re<1e5)*kf_low+Re(Re>=1e5)*kf_high;
%                             dh_tw = kf*(rho_4+rho_6)/2*U_4^3*r_4^2/(2*m_dt*W_6m^2);
%-------------------------------------------------------------------------%
%----------Resulting Losses and  Efficiency-------------------------------%
%-------------------------------------------------------------------------%
            j_46 = dh_til+dh_tf+dh_tsf+dh_ttc+dh_te;
            j_46_old = j_46;
            w_t46q = y_46+j_46+0.5*(C_6^2-C_4^2);
            
            %change in total enthalpy:
            dh_46tt = cp*(T_4t-T_6t);
            eta_pts = w_t46q/(y_46-0.5*(C_4^2));
            eta_error = abs(eta_pts-eta_pts_old);
            eta_sts = dh_46tt/dh_46sts;
            eta_stt = dh_46tt/dh_46stt;
            
            %residuals calculation:
            v_res_eta_pts (iteration_index) = abs(eta_pts-eta_pts_old)/eta_pts;
            v_res_r_4 (iteration_index) = abs(r_4-r_4_old)/r_4;
            v_res_beta_6m (iteration_index) = abs(beta_6m-beta_6m_old)/beta_6m;
            eta_pts_old = eta_pts;
            r_4_old = r_4;
            beta_6m_old = beta_6m;
            
            %Calculate wall spacing for CFD based on relative velocity:
            %https://www.pointwise.com/yplus/
            %             %hydraulic length:
            L_h = L_ms;
            L_h_ceti = L_ms_ceti;
            %hydraulic diameter - average inlet and outlet:
            D_h = 0.5*((4*pi*r_4*b_4/(2*pi*r_4+Z_r*b_4)+(2*pi*(r_6s^2-r_6h^2)/(pi*(r_6s-r_6h)+Z_r*b_6))));
            D_h_ceti = D_h;
            %mean relative velocity:
            W_m = (W_4+(W_6s+W_6h)/2)/2;

            %Reynolds number in relative system:
            Re_W = W_m * D_h / (mu_m/((rho_6+rho_4)/2));
           
            C_fCFD = 0.026/(Re_W^(1/7));
            tau_wall = C_fCFD*(rho_4+rho_6)/2*W_m^2/2;
            U_fric = sqrt(tau_wall/((rho_4+rho_6)/2));
            %resulting wall spacing for requested yplus value:
            delta_s = y_plus*mu_m/(U_fric*(rho_4+rho_6)/2);
            
            iteration_index = iteration_index+1;
            %do not allow more than maximum number of iterations:
            if iteration_index>maximum_iterations
                disp(['Error: Iteration index exceeded at Psi = ' num2str(Psi) ' Phi = ' num2str(Phi)]);
                disp(['eta error: ' num2str(eta_error*100) ' %']);
                disp(['calculated eta_pts = ' num2str(eta_pts*100) ' %']);
                valid_design = 0;
                break;
            end
            
            if w_t46q>0||not(isreal(U_4))
            disp(['Error: Positive work output at Psi = ' num2str(Psi) ' Phi = ' num2str(Phi)]);
            valid_design = 0;
            break;
            end
        end
        
        %save data of current iteration in vectors:
        %polytropic total to static efficiency:
        v_eta_pts(i,j) = eta_pts;
        v_eta_sts(i,j) = eta_sts;
        v_P_out(i,j) = w_t46q*m_dt;
        %size parameter
        VH(i,j) = sqrt(C_m6m*A_6)/dh_46sts^0.25;
        %velocity for isentropic expansion:
        spouting_velocity = sqrt(dh_46sts*2);
        v_blade_speed_ratio(i,j) = U_4/spouting_velocity;
        v_valid_design (i,j)=valid_design;
        v_r4 (i,j) = r_4;
        v_r6h(i,j) = r_6h;
        v_r6s(i,j) = r_6s;
        v_zr(i,j) = z_r; %axial length
        v_rc(i,j)=r_c; %curvature radius
        %losses:
        v_loss(i,j,:)=[dh_til;dh_tf;dh_tsf;dh_ttc;dh_te;dh_tke];
        v_loss_rel(i,j,:)=[dh_til;dh_tf;dh_tsf;dh_ttc;dh_te;dh_tke]/sum([dh_til;dh_tf;dh_tsf;dh_ttc;dh_te;dh_tke]);
        v_epsilon(i,j)=epsilon;    %radius ratio r6s/r4
%         v_beta_6bm(i_r,j_c)=beta_6bm/pi*180;
        v_beta_6m (i,j) = beta_6m/pi*180;
% % % % % % % % %         v_beta_6bs(i_r,j_c)=beta_6bs/pi*180;
        v_alpha_4 (i,j) = alpha_4/pi*180;
        v_Z_r(i,j)=Z_r;
        v_epsilon_rms(i,j)=epsilon_rms;
        v_s (i,j) = s;  %blade solidity
        v_Lms(i,j) = L_ms; %meridional length
        %% Plots for single Geometry
        if size(vPsi,2)==1
            % plot hub and shroud bezier spline contour:
            subplot(2,2,1)
            plot(Phub(1,:),Phub(2,:),'*--','Color','black');
            hold on;plot(Rhub(1,:),Rhub(2,:),'Color','blue');
            plot(Pshroud(1,:),Pshroud(2,:),'*--','Color','black');
            hold on;plot(Rshroud(1,:),Rshroud(2,:),'Color','blue');axis equal
            
%             %plot turbomachinery 3d geometry:
%             subplot(2,2,2)
%             r = Rhub(2,:);
%             z1 = Rhub(1,:);
%             phi_i = linspace(0,2*pi,length(r));
%             X_hub = r.*cos(phi_i');
%             Y_hub = r.*sin(phi_i');
%             Z_hub = repmat(z1,length(phi_i),1);
%             
%             r = Rshroud(2,:);
%             z1 = Rshroud(1,:);
%             X_shroud= r.*cos(phi_i');
%             Y_shroud = r.*sin(phi_i');
%             Z_shroud = repmat(z1,length(phi_i),1);
%             
%             hub = surf(X_hub,Y_hub,Z_hub);
%             hub.FaceColor=[ 0.5843    0.8157    0.9882];hold on;
%             shroud = surf(X_shroud,Y_shroud,Z_shroud);
%             shroud.FaceColor=[ 0.5843    0.8157    0.9882];
%             alpha(shroud,.5)
%             hold on; axis equal;
%             plot3(x_ml, y_ml, z_ml,'LineWidth',3)
%             
            subplot(2,2,2)
            %plot velocity triangles at inlet and outlet
            hold on;
            axis equal;
            w_in = quiver([0],[0],[W_u4], -[W_m4],'Color','black','LineStyle','--','AutoScale','off');
            c_in = quiver([0],[0],[C_u4], -[C_m4],'Color','black','AutoScale','off');
            u_in = quiver([W_u4+U_4],-[W_m4],[-U_4], [0],'Color','black','AutoScale','off');
            
            w_out = quiver([0],[0],[W_u6m], -[W_m6m],'Color',[0.75 0.75 0.75],'LineStyle','--','AutoScale','off');
            c_out = quiver([0],[0],[C_u6m], -[C_m6m],'Color',[0.75 0.75 0.75],'AutoScale','off');
            u_out = quiver([W_u6m+U_6m],-[W_m6m],[-U_6m], [0],'Color',[0.75 0.75 0.75],'AutoScale','off');
axis equal;
            disp(['inlet radial velocity: ' num2str(C_m4) ' [m/s]'])
            disp(['outlet axial velocity: ' num2str(C_m6m) ' [m/s]'])
            disp(['outlet hub diameter: ' num2str(2*r_6h*1000) ' [mm]'])
            disp(['outlet shroud diameter: ' num2str(2*r_6s*1000) ' [mm]'])
            alpha_4_deg = alpha_4/pi*180;
            beta_4_deg = beta_4/pi*180;
            hub_diameter = 2000*r_6h;
            shroud_diameter = 2000*r_6s;
            inlet_diameter = 2000*r_4;
            T = table(rpm,inlet_diameter,shroud_diameter,hub_diameter,eta_sts,eta_pts,alpha_4_deg,beta_4_deg)
                      
            %plot loss distribution pie chart for current design:
            subplot(2,2,3)
            pie([dh_til;dh_tf;dh_tsf;dh_ttc;dh_te;dh_tke]);
            legend({'incidence','passage','secondary flow','tip clearance','trailing edge','exit losses'});
            disp(['eta_s,ts = ' num2str(eta_sts*100) ' %'])
            disp(['eta_s,tt = ' num2str(eta_stt*100) ' %'])
            disp(['CFD: wall spacing for y+ = ' num2str(y_plus) ': ' num2str(delta_s) ' m'])
            
%                     %             %plot Nozzle geometry:
%                     subplot(2,2,4)
%                     %plot inner and outer leading edge circles:
%                     phi = linspace(0,2*pi,30);
%                     x1 = r_1*cos(phi);
%                     y1 = r_1*sin(phi);
%                     x2 = r_3*cos(phi);
%                     y2 = r_3*sin(phi);
%                     xr4 = r_4*cos(phi);
%                     yr4 = r_4*sin(phi);
%                     xr6s = r_6s*cos(phi);
%                     yr6s = r_6s*sin(phi);
%                     xr6h = r_6h*cos(phi);
%                     yr6h = r_6h*sin(phi);
%                     plot(x1,y1); hold on; plot(x2,y2); hold on;axis equal; plot(xr4,yr4,'Color','black');plot(xr6s,yr6s,'Color','black');plot(xr6h,yr6h,'Color','black');
%                     for psi = linspace(0,2*pi,Z_s)
%                     %rotation of camber line:
%                     x3 = P_gv_start(1)*cos(psi)-P_gv_start(2)*sin(psi);
%                     y3 = P_gv_start(1)*sin(psi)+P_gv_start(2)*cos(psi);
%                     x4 = P_gv_end(1)*cos(psi)-P_gv_end(2)*sin(psi);
%                     y4 = P_gv_end(1)*sin(psi)+P_gv_end(2)*cos(psi);
%                     line([x3 x4],[y3 y4],'Linestyle','-.'); hold on;
%                     end
                    %residuals plots:
                    subplot(2,2,4)
                    plot(2:1:iteration_index,v_res_r_4); hold on
                    plot(2:1:iteration_index,v_res_eta_pts);
                    plot(2:1:iteration_index,v_res_beta_6m);
                    legend({'r_4','\eta_{pts}','\beta_{6m}'});
        end
        
        
        

        %             %
        % figure(10)
        %                     if valid_design==1
        % plot3(Psi,Phi,2000*r_4,'^','Color','blue'); hold on
        % % plot3(Psi,Phi,eta_sts,'^','Color','red'); hold on
        %                     xlabel('Psi');ylabel('Phi');zlabel('\eta_p')
        %                     title('polytropic efficiency as function of disc diameter
        %                     plot(2000*r_4,eta_pts,'^','Color','black');hold on;
        %                     xlabel('D_4');ylabel('\eta_{pts}');
        
    end
end

% %
% end
% %% Full Data Plots
if size(vPsi,2)>1
    %------------------Efficiency and Losses-----------------------
    %plot contour of eta as function of Psi and Phi:
    figure(1)
    subplot(2,2,1)
    %plot contour lines with text:
    eta = v_eta_sts.*v_valid_design;
    eta(eta==0)=nan;
    eta_levels = ceil(min(eta(:))*100):1:round(max(eta(:)*100));
    h = contour(vPsi, vPhi, round(eta*100,2)',eta_levels,'ShowText','on','Color','black');hold on;
    title('Polytropic Total to Static Efficiency as Function of \Phi and \Psi');
    xlabel('\Psi');ylabel('\Phi');
    v_invalid_design = ~v_valid_design;
    Psiinvalid = v_invalid_design.*vPsi'; Psiinvalid(Psiinvalid==0)=[];
    Phiinvalid = v_invalid_design.*vPhi; Phiinvalid(Phiinvalid==0)=[];
    P = [Psiinvalid(:) Phiinvalid(:)];
    [k,av] = boundary(P);
    
    subplot(2,2,2)
    loss_levels = 0:5:100;
    %plot relative amount of tip clearance losses as function of Psi and Phi:
    tc_rel = v_loss_rel(:,:,4).*v_valid_design;
    tc_rel(tc_rel==0)=nan;
    h = contour(vPsi, vPhi, round(tc_rel*100,2)',loss_levels,'ShowText','on','Color','black');hold on;
    title('Losses: Tip Clearance Losses (Relative)');
    xlabel('\Psi');ylabel('\Phi');
    
    subplot(2,2,3)
    %plot relative amount of secondary flow losses as function of Psi and Phi:
    sec_rel = v_loss_rel(:,:,3).*v_valid_design;
    sec_rel(sec_rel==0)=nan;
    h = contour(vPsi, vPhi, round(sec_rel*100,2)',loss_levels,'ShowText','on','Color','black');hold on;
    title('Losses: Secondary Flow (Relative)');
    xlabel('\Psi');ylabel('\Phi');
    
    subplot(2,2,4)
    %plot relative amount of exit kinetic flow losses as function of Psi and Phi:
    sec_rel = v_loss_rel(:,:,6).*v_valid_design;
    sec_rel(sec_rel==0)=nan;
    h = contour(vPsi, vPhi, (sec_rel*100)',loss_levels,'ShowText','on','Color','black');hold on;
    title('Losses: Kinetic Exit Energy (Relative)');
    xlabel('\Psi');ylabel('\Phi');
    
    %------------------Geometry------------------------------------
    figure(5)
    subplot(2,2,1);
    %plot inlet diameter as function of Psi and Phi:
    D_4 = v_r4*2000.*v_valid_design;
    D_4(D_4==0)=nan;
    h = contour(vPsi, vPhi, (D_4)','ShowText','on','Color','black');hold on;
    title('Geometry: Inlet Diameter [mm]');

    
    subplot(2,2,2);
    v_epsilon=v_epsilon.*v_valid_design;
    v_epsilon(v_epsilon==0)=nan;
    %plot radius ratio r6s/r4 as function of Psi and Phi:
    h = contour(vPsi, vPhi, v_epsilon','ShowText','on','Color','black');hold on;
    title('Geometry: Rms Radius Ratio r_{6rms} / r_4');

    
    subplot(2,2,3);
    %     %plot axial length as function of Psi and Phi:
    %     h = contour(vPsi, vPhi, (v_zr*1000)','ShowText','on','Color','black');hold on;
    %     title('Geometry: Passage axial length [mm]');
    %plot number of vanes as function of Psi and Phi:
    v_Z_r=v_Z_r.*v_valid_design;
    v_Z_r(v_Z_r==0)=nan;
    h = contour(vPsi, vPhi, (v_Z_r)','ShowText','on','Color','black');hold on;
    title('Geometry: Number of Rotor Vanes');
    
    subplot(2,2,4);
    beta_levels = 0:-2:-100;
    v_beta_6m=v_beta_6m.*v_valid_design;
    v_beta_6m(v_beta_6m==0)=nan;
    %plot blade angle at mid-span at turbine outlet
    h = contour(vPsi, vPhi, v_beta_6m',beta_levels,'ShowText','on','Color','black');hold on;
    title('Geometry: blade outlet angle [�]');

end

%% Functions
