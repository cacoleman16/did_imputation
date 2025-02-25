/*
	This simulated example illustrates how to estimate causal effects with event studies using a range of methods
	and plot the coefficients & confidence intervals using the event_plot command.
	
	Date: 28/05/2021
	Author: Kirill Borusyak (UCL), k.borusyak@ucl.ac.uk
	
	You'll need the following commands:
		- did_imputation (Borusyak et al. 2021): currently available at https://github.com/borusyak/did_imputation
		- did_multiplegt (de Chaisemartin and D'Haultfoeuille 2020): available on SSC
		- eventstudyinteract (San and Abraham 2020): available on SSC
		- scdid (Callaway and Sant'Anna 2020): currently available at https://friosavila.github.io/playingwithstata/main_csdid.html

*/

// Generate a complete panel of 300 units observed in 15 periods
clear all
timer clear
set seed 10
global T = 15
global I = 300

set obs `=$I*$T'
gen i = int((_n-1)/$T )+1 					// unit id
gen t = mod((_n-1),$T )+1					// calendar period
tsset i t

// Randomly generate treatment rollout years uniformly across Ei=10..16 (note that periods t>=16 would not be useful since all units are treated by then)
gen Ei = ceil(runiform()*7)+$T -6 if t==1	// year when unit is first treated
bys i (t): replace Ei = Ei[1]
gen K = t-Ei 								// "relative time", i.e. the number periods since treated (could be missing if never-treated)
gen D = K>=0 & Ei!=. 						// treatment indicator

// Generate the outcome with parallel trends and heterogeneous treatment effects
gen tau = cond(D==1, (t-12.5), 0) 			// heterogeneous treatment effects (in this case vary over calendar periods)
gen eps = rnormal()							// error term
gen Y = i + 3*t + tau*D + eps 				// the outcome (FEs play no role since all methods control for them)

// Estimation with did_imputation of Borusyak et al. (2021)
timer on 1
did_imputation Y i t Ei, allhorizons pretrend(5)
timer off 1
event_plot, default_look graph_opt(xtitle("Periods since the event") ytitle("Average causal effect") ///
	title("Borusyak et al. (2021) imputation estimator") xlabel(-3(1)4))

estimates store bjs // storing the estimates for later

// Estimation with did_multiplegt of de Chaisemartin and D'Haultfoeuille (2020)
timer on 2
did_multiplegt Y i t D, robust_dynamic dynamic(5) placebo(5) breps(100) cluster(i) 
timer off 2
event_plot e(estimates)#e(variances), default_look graph_opt(xtitle("Periods since the event") ytitle("Average causal effect") ///
	title("de Chaisemartin and D'Haultfoeuille (2020)") xlabel(-4(1)4)) stub_lag(Effect_#) stub_lead(Placebo_#) together

matrix dcdh_b = e(estimates) // storing the estimates for later
matrix dcdh_v = e(variances)

// Estimation with cldid of Callaway and Sant'Anna (2020)
gen gvar = cond(Ei==., 0, Ei) // group variable as required for the csdid command
timer on 3
csdid Y, ivar(i) time(t) gvar(gvar) notyet
estat event, estore(cs) // this produces and stores the estimates at the same time
timer off 3
event_plot cs, default_look graph_opt(xtitle("Periods since the event") ytitle("Average causal effect") xlabel(-9(1)4) ///
	title("Callaway and Sant'Anna (2020)")) stub_lag(E#) stub_lead(E_#) together

// Estimation with eventstudyinteract of Sun and Abraham (2020)
sum Ei
gen lastcohort = Ei==r(max) // dummy for the latest- or never-treated cohort
forvalues l = 0/5 {
	gen L`l'event = K==`l'
}
forvalues l = 1/14 {
	gen F`l'event = K==-`l'
}
drop F1event // normalize K=-1 (and also K=-15) to zero
timer on 4
eventstudyinteract Y L*event F*event, vce(cluster i) absorb(i t) cohort(Ei) control_cohort(lastcohort)
timer off 4
event_plot e(b_iw)#e(V_iw), default_look graph_opt(xtitle("Periods since the event") ytitle("Average causal effect") xlabel(-9(1)4) ///
	title("Sun and Abraham (2020)")) stub_lag(L#event) stub_lead(F#event) together

matrix sa_b = e(b_iw) // storing the estimates for later
matrix sa_v = e(V_iw)

// TWFE OLS estimation (which is correct here because of treatment effect homogeneity). Some groups could be binned.
timer on 5
reghdfe Y F*event L*event, a(i t) cluster(i)
timer off 5
event_plot, default_look stub_lag(L#event) stub_lead(F#event) together graph_opt(xtitle("Days since the event") ytitle("OLS coefficients") xlabel(-4(1)4) ///
	title("OLS"))

estimates store ols // saving the estimates for later

// Construct the vector of true average treatment effects by the number of periods since treatment
matrix btrue = J(1,6,.)
matrix colnames btrue = tau0 tau1 tau2 tau3 tau4 tau5
qui forvalues h = 0/5 {
	sum tau if K==`h'
	matrix btrue[1,`h'+1]=r(mean)
}

// Measure the times each estimator takes
qui timer list
local bjs_time = strofreal(r(t1),"%5.1f")
local dcdh_time = strofreal(r(t2),"%5.1f")
local cs_time = strofreal(r(t3),"%5.1f")
local sa_time = strofreal(r(t4),"%5.1f")
local ols_time = strofreal(r(t5),"%5.1f")

// Combine all plots using the stored estimates
event_plot btrue# bjs dcdh_b#dcdh_v cs sa_b#sa_v ols, ///
	stub_lag(tau# tau# Effect_# E# L#event L#event) stub_lead(pre# pre# Placebo_# E_# F#event F#event) plottype(scatter) ciplottype(rcap) ///
	together perturb(-0.325(0.13)0.325) trimlead(5) noautolegend ///
	graph_opt(title("Event study estimators in a simulated panel (300 units, 15 periods)") ///
		xtitle("Periods since the event") ytitle("Average causal effect") xlabel(-5(1)5) ylabel(0(1)3) ///
		legend(order(1 "True value" 2 "Borusyak et al. [`bjs_time' seconds]" 4 "de Chaisemartin-D'Haultfoeuille [`dcdh_time's]" ///
				6 "Callaway-Sant'Anna [`cs_time's]" 8 "Sun-Abraham [`sa_time's]" 10 "OLS [`ols_time's]") rows(3) region(style(none))) ///
	/// the following lines replace default_look with something more elaborate
		xline(-0.5, lcolor(gs8) lpattern(dash)) yline(0, lcolor(gs8)) graphregion(color(white)) bgcolor(white) ylabel(, angle(horizontal)) ///
	) ///
	lag_opt1(msymbol(+) color(cranberry)) lag_ci_opt1(color(cranberry)) ///
	lag_opt2(msymbol(O) color(cranberry)) lag_ci_opt2(color(cranberry)) ///
	lag_opt3(msymbol(Dh) color(navy)) lag_ci_opt3(color(navy)) ///
	lag_opt4(msymbol(Th) color(forest_green)) lag_ci_opt4(color(forest_green)) ///
	lag_opt5(msymbol(Sh) color(dkorange)) lag_ci_opt5(color(dkorange)) ///
	lag_opt6(msymbol(Oh) color(purple)) lag_ci_opt6(color(purple)) 
graph export "five_methods_combined.png", replace
