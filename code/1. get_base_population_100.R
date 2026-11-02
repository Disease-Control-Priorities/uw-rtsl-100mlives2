#...........................................................
# Documentation ----
#...........................................................

# The input of this file is the GBD 2019 data and the GBD 2019 population estimates.
# The output of this file is a data.csv file with the baseline rates for each country and year.
# The output data set includes the following columns: sex	age	location	year	ALL.mx	BG.mx.all	cause	BG.mx	PREVt0	DIS.mx.t0	Nx


#...........................................................
# UN WPP Data ----
#...........................................................

# Compute age 20 population projections from UN WPP data
# Copyright © 2024 by United Nations, made available under a Creative Commons license CC BY 3.0 IGO: http://creativecommons.org/licenses/by/3.0/igo/
# Suggested citation: United Nations, Department of Economic and Social Affairs, Population Division (2024). World Population Prospects 2024, Online Edition.


file_unwpp <- file.path(wd_raw, "UN2024", "WPP2024_POP_F01_3_POPULATION_SINGLE_AGE_FEMALE.xlsx")

# read the ESTIMATES sheet, range A17:DH22000, then convert to data.table
dt_unwpp_f <- read_excel(
  path       = file_unwpp,
  sheet      = "Estimates",
  range      = "A17:DH22000",
  col_names  = TRUE
) %>% 
  as.data.table()

dt_unwpp_f[,sex:="Female"]

file_unwpp <- file.path(wd_raw, "UN2024", "WPP2024_POP_F01_2_POPULATION_SINGLE_AGE_MALE.xlsx")

# read the ESTIMATES sheet, range A17:DH22000, then convert to data.table
dt_unwpp_m <- read_excel(
  path       = file_unwpp,
  sheet      = "Estimates",
  range      = "A17:DH22000",
  col_names  = TRUE
) %>% 
  as.data.table()

dt_unwpp_m[,sex:="Male"]
                      
# combine the two data.tables

dt_unwpp <- rbind(dt_unwpp_f, dt_unwpp_m)

setcolorder(dt_unwpp,"sex")

# melt everything except the first 12 cols
dt_unwpp_estimates <- melt(dt_unwpp,
  id.vars        = names(dt_unwpp)[1:12], 
  variable.name  = "age",                         
  value.name     = "Nx"                      
)

dt_unwpp_estimates[,year_id:=Year]

dt_unwpp_estimates[,age:=as.numeric(age)]
dt_unwpp_estimates[,location:=`Region, subregion, country or area *`]
dt_unwpp_estimates[,Nx:=as.numeric(Nx)*1000]

dt_unwpp_estimates <- dt_unwpp_estimates[Type=="Country/Area",
                                         c("Nx","year_id","location","sex","age"),with = F]

# read the MEDIUM VARIANT sheet, range A17:DH22000, then convert to data.table
file_unwpp <- file.path(wd_raw, "UN2024", "WPP2024_POP_F01_3_POPULATION_SINGLE_AGE_FEMALE.xlsx")

# read the ESTIMATES sheet, range A17:DH22000, then convert to data.table
dt_unwpp_f <- read_excel(
  path       = file_unwpp,
  sheet      = "Medium variant",
  range      = "A17:DH22000",
  col_names  = TRUE
) %>% 
  as.data.table()

dt_unwpp_f[,sex:="Female"]

file_unwpp <- file.path(wd_raw, "UN2024", "WPP2024_POP_F01_2_POPULATION_SINGLE_AGE_MALE.xlsx")

# read the ESTIMATES sheet, range A17:DH22000, then convert to data.table
dt_unwpp_m <- read_excel(
  path       = file_unwpp,
  sheet      = "Medium variant",
  range      = "A17:DH22000",
  col_names  = TRUE
) %>% 
  as.data.table()

dt_unwpp_m[,sex:="Male"]

# combine the two data.tables

dt_unwpp <- rbind(dt_unwpp_f, dt_unwpp_m)

setcolorder(dt_unwpp,"sex")

# melt everything except the first 12 cols
dt_unwpp_projections <- melt(dt_unwpp,
                           id.vars        = names(dt_unwpp)[1:12], 
                           variable.name  = "age",                         
                           value.name     = "Nx"                      
)

dt_unwpp_projections[,year_id:=Year]

dt_unwpp_projections[,age:=as.numeric(age)]
dt_unwpp_projections[,location:=`Region, subregion, country or area *`]
dt_unwpp_projections[,Nx:=as.numeric(Nx)*1000]

dt_unwpp_projections <- dt_unwpp_projections[Type=="Country/Area",
                                         c("Nx","year_id","location","sex","age"),with = F]


dt_unwpp_projections <- rbind(dt_unwpp_estimates, dt_unwpp_projections)


# Fix names to match GBD

# Fix countries names
dt_unwpp_projections[location == "Türkiye", location := "Turkey"]
dt_unwpp_projections[location == "Côte d'Ivoire", location := "Ivory Coast"]

name_map <- c(
  "United Republic of Tanzania" = "Tanzania",
  "United States of America" = "United States",
  "China, Taiwan Province of China" = "Taiwan (Province of China)",
  "Dem. People's Republic of Korea" = "Democratic People's Republic of Korea",
  "Bolivia (Plurinational State of)" = "Bolivia",
  "Micronesia (Fed. States of)"     = "Micronesia (Federated States of)", 
  "State of Palestine" =   "Palestine"
)
dt_unwpp_projections[, location := fcoalesce(name_map[location], location)]


locs_unwpp <- unique(dt_unwpp_projections$location)

# PopulationsAge20_2050 ----

# Nx	year_id	location	sex	age year 2010 to year 2050
fwrite(dt_unwpp_projections[age==20,],
  file = paste0(wd_data,"UN2024/","PopulationsAge20_2050.csv"),
  row.names = FALSE
)

# PopulationsAge20_full ----

# Nx	year_id	location	sex	age year 2010 to year 2050
fwrite(dt_unwpp_projections[age==20,],
       file = paste0(wd_data,"UN2024/","PopulationsAge20_full.csv"),
       row.names = FALSE
)

# PopulationsSingleAge0050 ----

saveRDS(dt_unwpp_projections[year_id>=2000,],
      file = paste0(wd_data,"UN2024/","PopulationsSingleAge0050.rds"))

# Clean up the data.tables
rm(dt_unwpp_f, dt_unwpp_m, file_unwpp, dt_unwpp, dt_unwpp_estimates,dt_unwpp_projections)


#...........................................................
# IHME POP Projections ----
#...........................................................

setwd(paste0(wd_raw,"GBD-POP"))

# Compute age 20 population projections from UN WPP data

# Estimates single year
# 2000 - 2017
# build vector of years and corresponding file names
years <- 2000:2019
files <- sprintf("IHME_GBD_2019_POP_SYA_%d_Y2021M01D28.csv", years)

# read & stack them in one go
gbdpop <- rbindlist(lapply(files, fread))

# Filter out rows where sex is "both" and location_id equals 533 (Georgia the state)
gbdpop <- gbdpop[sex_name != "both" & location_id != 533]

# Create/modify age_group column from age_group_name
gbdpop[, age_group := as.numeric(age_group_name)]
gbdpop[age_group_name == "<1 year", age_group := 0]
gbdpop[age_group_name == "95 plus", age_group := 95]

# Rename the second column to "location" (using positional renaming)
setnames(gbdpop, 2, "location")

# Create totalpop by adding the iso3 code using countrycode
totalpop <- copy(gbdpop)
totalpop[, iso3 := countrycode(location, "country.name", "iso3c")]

# Standardize sex names to title case
totalpop[sex_name == "male", sex_name := "Male"]
totalpop[sex_name == "female", sex_name := "Female"]

# Fix countries names
totalpop[location == "Türkiye", location := "Turkey"]
totalpop[location == "Côte d'Ivoire", location := "Ivory Coast"]

totalpop_baseline_ihme    <- totalpop[year_id>=2000 & age_group > 19,
                                      .(year=year_id, location,iso3, sex = sex_name, age = age_group, Nx = val)]

saveRDS(totalpop_baseline_ihme, file = paste0(wd_raw,"GBD/","totalpop_baseline_ihme.rds"))


