
#...........................................................
# Sodium data ----
#...........................................................

data.in<-fread(paste0(wd,"bp_data6.csv"))%>%rename(location = location_gbd)%>%select(-Year, -Country)

data.in$salt[data.in$location=="China"]<-4.83*2.54
length(unique(data.in$location))

# rename locations to match gbd locations (the baseline)
name_map <- c(
  "Brunei"                            = "Brunei Darussalam",
  "Cape Verde"                        = "Cabo Verde",
  "Cote d'Ivoire"                     = "Ivory Coast",
  "Czech Republic"                    = "Czechia",
  "Federated States of Micronesia"    = "Micronesia (Federated States of)",
  "Iran"                              = "Iran (Islamic Republic of)",
  "Laos"                              = "Lao People's Democratic Republic",
  "Macedonia"                         = "North Macedonia",
  "Moldova"                           = "Republic of Moldova",
  "South Korea"                       = "Republic of Korea",
  "Swaziland"                         = "Eswatini",
  "Syria"                             = "Syrian Arab Republic",
  "The Bahamas"                       = "Bahamas",
  "The Gambia"                        = "Gambia",
  "Venezuela"                         = "Venezuela (Bolivarian Republic of)",
  "Vietnam"                           = "Viet Nam",
  "North Korea"                       = "Democratic People's Republic of Korea",
  "United States of America"          = "United States",
  "Tanzania"                          = "United Republic of Tanzania",
  "Bolivia"                           = "Bolivia (Plurinational State of)",
  "Taiwan"                            = "Taiwan (Province of China)"
)

data.in[, location := fcoalesce(name_map[location], location)]

# Keep only average salt consumption. We do not have heterogeneity in age/sex salt consumption
 
dt_sodium_model <- unique(data.in[,.(location,salt),with=T])


# New IHME salt data

dt_sodium_ihme <- fread(paste0(wd_raw,"TFAPolicy/","Diet/","IHME_GBD_2023_DIET_RISK_1990_2024_SODIUM_Y2024M11D05.csv"))

dt_sodium_ihme <- dt_sodium_ihme[,c("year_id","location_name","sex_name","age_group_name","val","upper","lower","age_group_id"),with = F]

setnames(dt_sodium_ihme,c("year_id","location_name","sex_name","age_group_name","val","upper","lower"),
         c("year","location","sex","age","sodium_current","sodium_current_upper","sodium_current_lower"))

dt_sodium_ihme <- dt_sodium_ihme[location!="Global",]

name_map <- c(
  "United States of America"          = "United States",
  "Taiwan"                            = "Taiwan (Province of China)"
)

dt_sodium_ihme[, location := fcoalesce(name_map[location], location)]


# Only covers from 25 years and older, so imputing for 20-24 yearsas 25-29 years

dt_sodium_ihme_20 <- dt_sodium_ihme[age == "25 to 29",]
dt_sodium_ihme_20[, age := "20 to 24"]
dt_sodium_ihme <- rbind(dt_sodium_ihme, dt_sodium_ihme_20)

rm(dt_sodium_ihme_20)


dt_sodium_ihme <- dt_sodium_ihme[sex!="Both",]

# Fix countries names
dt_sodium_ihme[location == "Türkiye", location := "Turkey"]
dt_sodium_ihme[location == "Côte d'Ivoire", location := "Ivory Coast"]

# Change data.in names before merge

# merge model and IHME and save
dt_sodium <- merge(dt_sodium_ihme,dt_sodium_model, by = c("location"), all.x = TRUE, all.y = TRUE)

dt_check <- dt_sodium[is.na(sodium_current),] # check is null

# Save the data
saveRDS(dt_sodium, file = paste0(wd_data,"Sodium/", "sodium_data.rds"))

# cleaning: remove objects that are no longer needed
rm(dt_sodium_model, dt_sodium_ihme, data.in, name_map, dt_check,dt_sodium)

#...........................................................
# Blood Pressure data ----
#...........................................................
#source("get_bp2022.R")


#...........................................................
# TFA data ----
#...........................................................


#DT AI not included
#dt_tfa <- fread(paste0(wd_raw,"TFAPolicy/","tfa_intake.csv"))
# Extract first numeric value (including decimals)
# dt_tfa[, tfa_current := as.numeric(stringr::str_extract(`Mean TFA Intake (%E)`, "\\d+\\.?\\d*"))]


# Input from IHME
dt_tfa <- fread(paste0(wd_raw,"TFAPolicy/","Diet/","IHME_GBD_2023_DIET_RISK_1990_2024_TRANSFAT_Y2024M11D05",".csv"))

dt_tfa <- dt_tfa[,c("year_id","location_name","sex_name","age_group_name","val","upper","lower","age_group_id"),with = F]

setnames(dt_tfa,c("year_id","location_name","sex_name","age_group_name","val","upper","lower"),
               c("year","location","sex","age","tfa_current","tfa_current_upper","tfa_current_lower"))

dt_tfa <- dt_tfa[location!="Global",]

# rename locations
dt_tfa[location == "Türkiye", location := "Turkey"]
dt_tfa[location == "Côte d'Ivoire", location := "Ivory Coast"]

# Only covers from 25 years and older, so imputing for 20-24 yearsas 25-29 years

dt_tfa_20 <- dt_tfa[age == "25 to 29",]
dt_tfa_20[, age := "20 to 24"]
dt_tfa <- rbind(dt_tfa, dt_tfa_20)

rm(dt_tfa_20)

# Countries with BPP

dt_tfa_bpp <- as.data.table(read_excel(paste0(wd_raw,"TFAPolicy/", "List of Countries with Policies Passed.xlsx"), 
                                       sheet = "Sheet1", range = "A3:C53")) 

# rename locations to match gbd locations (the baseline)
name_map <- c(
  "Czech Republic"                    = "Czechia",
  "Macedonia"                         = "North Macedonia",
  "Moldova"                           = "Republic of Moldova",
  "Cyprus"                            = "Republic of Cyprus")

dt_tfa_bpp[, Country := fcoalesce(unname(name_map[Country]), Country)]

#? Leichtein has no tfa data but policy
dt_tfa <- merge(dt_tfa, dt_tfa_bpp, by.x = "location", by.y= "Country", all.x = TRUE,all.y = F)

# check locations
dt_check <- dt_tfa[is.na(sex),]

setnames(dt_tfa, c("Date passed", "Date in Effect"),
                 c("tfa_bpp_date_passed", "tfa_bpp_date_in_effect"))

#dt_tfa <- dt_tfa[, .(location, tfa_current, tfa_bpp_date_passed, tfa_bpp_date_in_effect)]

dt_tfa <- dt_tfa[sex!="Both",]

# Save the data
saveRDS(dt_tfa, file = paste0(wd_data,"TFAPolicy/", "tfa_data.rds"))

# cleaning: remove objects that are no longer needed
rm(dt_tfa, dt_tfa_bpp,dt_check)


#...........................................................
# Statins/Lipid data ----
#...........................................................

# High Fasting Plasma Glucose (FPG) data

# Attributable Fractions for Statins (IHD and Ischemic Stroke) GBD Compare 2021
#http://ihmeuw.org/72j1

af_statins_ihd <- fread(paste0(wd_raw,"Statins/","AF_HighPlasmaGlucose_IHD.csv"))

af_statins_istroke <- fread(paste0(wd_raw,"Statins/","AF_HighPlasmaGlucose_IschemicStroke.csv"))

# Append the two data tables

af_statins <- rbind(af_statins_ihd, af_statins_istroke)

setnames(af_statins, c("Location", "Cause of death or injury", "Value"),
         c("location", "cause", "af_statins"))

# Keep location,cause and value
af_statins <- af_statins[, .(location, cause, af_statins)]

# rename causes
af_statins[cause == "Ischemic heart disease", cause := "ihd"]
af_statins[cause == "Ischemic stroke", cause := "istroke"]

# check/remove if duplicates
af_statins <- unique(af_statins,by=c("location","cause"))


# rename locations to match gbd locations (the baseline)
name_map <- c(
  "United States of America"          = "United States",
  "Türkiye)"                          = "Turkey",
  "Côte d'Ivoire"                     = "Ivory Coast")

af_statins[, location := fcoalesce(name_map[location], location)]

# save the data
saveRDS(af_statins, file = paste0(wd_data,"Statins/","af_statins.rds"))

# cleaning: remove objects that are no longer needed
rm(af_statins_ihd, af_statins_istroke, af_statins, name_map)
