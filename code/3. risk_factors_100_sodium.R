
#...........................................................
# Sodium data ----
#...........................................................

#data.in<-fread(paste0(wd,"bp_data6.csv"))%>%rename(location = location_gbd)%>%select(-Year, -Country)

#data.in$salt[data.in$location=="China"]<-4.83*2.54
#length(unique(data.in$location))

# Input 80- 80-80

salt<-read.csv(paste0(wd_raw,"Sodium/","Adults (age 25+ years)_ Estimated per capita sodium intake_4-3-2021 11.50.csv"), 
               stringsAsFactors = F)%>%
  rename(iso3=AreaID, salt=DataValue,location=AreaName)%>%
  select(c(iso3, location, salt))
salt$salt<-salt$salt*2.54 #converting sodium to salt

salt <- as.data.table(salt)

salt[location=="China",salt:=4.83*2.54]

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

salt[, location := fcoalesce(name_map[location], location)]

# New IHME salt data

dt_sodium_ihme_19 <- fread(paste0(wd_raw,"Sodium/","IHME_GBD_2019_DIET_RISK_1990_2019_SODIUM_Y2021M09D27.csv"))
dt_sodium_ihme_19[,source:= "GBD 2019"]
dt_sodium_ihme_21 <- fread(paste0(wd_raw,"Sodium/","IHME_GBD_2021_DIET_RISK_1990_2021_SODIUM_Y2024M06D05.csv"))
dt_sodium_ihme_21[,source:= "GBD 2021"]
dt_sodium_ihme_23 <- fread(paste0(wd_raw,"Sodium/","IHME_GBD_2023_DIET_RISK_1990_2024_SODIUM_Y2024M11D05.csv"))
dt_sodium_ihme_23[,source:= "GBD 2023"]

dt_sodium_ihme <- rbind(dt_sodium_ihme_19,dt_sodium_ihme_21)
dt_sodium_ihme <- rbind(dt_sodium_ihme,dt_sodium_ihme_23, fill= T)

dt_sodium_ihme <- dt_sodium_ihme[year_id>=2017 & sex_name!="Both" & age_group_name!="25 plus",c("year_id","location_name","sex_name","age_group_name","val","upper","lower","age_group_id","source"),with = F]

setnames(dt_sodium_ihme, c("location_name","sex_name","age_group_name"),
         c("location", "sex", "age.group"))
# Population

dt_pop <- readRDS(file = paste0(wd_raw,"GBD/","totalpop_ihme.rds"))

dt_pop[, location := fcoalesce(name_map[location], location)]

dt_pop <- dt_pop[, .(location, year_id, sex_name, age_group_name, val),with=T]

setnames(dt_pop, c("val", "year_id","sex_name"),
         c("population","year","sex"))

age_match<-data.frame(age=20:95)%>%
  mutate(age.group = ifelse(age<25, "20 to 24", NA),
         age.group = ifelse(age>=25 & age<30, "25 to 29", age.group),
         age.group = ifelse(age>=30 & age<35, "30 to 34", age.group),
         age.group = ifelse(age>=35 & age<40, "35 to 39", age.group),
         age.group = ifelse(age>=40 & age<45, "40 to 44", age.group),
         age.group = ifelse(age>=45 & age<50, "45 to 49", age.group),
         age.group = ifelse(age>=50 & age<55, "50 to 54", age.group),
         age.group = ifelse(age>=55 & age<60, "55 to 59", age.group),
         age.group = ifelse(age>=60 & age<65, "60 to 64", age.group),
         age.group = ifelse(age>=65 & age<70, "65 to 69", age.group),
         age.group = ifelse(age>=70 & age<75, "70 to 74", age.group),
         age.group = ifelse(age>=75 & age<80, "75 to 79", age.group),
         age.group = ifelse(age>=80 & age<85, "80 to 84", age.group),
         age.group = ifelse(age>=85 & age<90, "85 to 89", age.group),
         age.group = ifelse(age>=90 & age<95, "90 to 94", age.group),
         age.group = ifelse(age==95, "95 plus", age.group))

age_match$age <- as.character(age_match$age)

dt_pop[age_group_name == "<1 year", age_group_name := "0"]
dt_pop[age_group_name == "95 plus", age_group_name := "95"]

dt_pop <- merge(dt_pop, age_match, by.x = "age_group_name", by.y = "age", all.x = TRUE)

# Average population by age group (not year because POp comes up to 2019)
dt_pop <- dt_pop[year==2017,list(population=mean(population)),by=list(location,sex,age.group)]

# Merge population data with sodium data
dt_sodium <- merge(dt_sodium_ihme,dt_pop,
                   by = c("location","sex","age.group"), all.x = TRUE,all.y = F)

# compute mean sodium intake per location
dt_sodium_mean <- dt_sodium[, .(salt_current = weighted.mean(val,population, na.rm = TRUE)*2.5),
                            by = list(year_id,location,source)]

# Merge population data with sodium data
dt_sodium <- merge(dt_sodium_mean,salt,
                   by = c("location"), all.x = TRUE,all.y = TRUE)
fwrite(dt_sodium,file=paste0(wd_raw,"dt_sodium_validation.csv"))


# Data form Powles et a.l 2013
# https://bmjopen.bmj.com/content/3/12/e003733.long#supplementary-materials

library(xml2)
library(data.table)
library(rvest)

# 1. Load the XML file
doc <- read_xml("C:/Users/wrgar/OneDrive - UW/02Work/ResolveToSaveLives/100MLives/data/raw/Sodium/10.1136_bmjopen-2013-003733.xml")

# 2. Find all table-wraps
tables <- xml_find_all(doc, ".//table-wrap")

# Optional: inspect table captions to find the right one
captions <- xml_text(xml_find_all(tables, ".//caption"))
cat(captions, sep = "\n\n")

# 3. Select Table 2 (assuming it's the second one, index might vary!)
table2 <- tables[[2]]

# 4. Extract all rows in the table
rows <- xml_find_all(table2, ".//tr")

# 5. Turn rows into lists of text
table_list <- lapply(rows, function(row) {
  cells <- xml_find_all(row, ".//td|.//th")
  xml_text(cells, trim = TRUE)
})

# 6. Convert to data.table (DON'T use names here)
dt <- as.data.table(do.call(rbind, table_list))

# 7. Use first row as column names
setnames(dt, as.character(dt[1, ]))
dt <- dt[-1]

# 8. Clean up (optional): rename columns and parse numbers
names(dt) <- tolower(gsub("[^[:alnum:]_]+", "_", names(dt)))


# Extract males, but is fine. It is total 2010
dt[, sodium_powles_2010 := as.numeric(sub("^(\\d+\\.\\d+).*", "\\1", males))]
setnames(dt,"","location")

dt <- dt[location!="",c("location","sodium_powles_2010"),with=F]

# Step 1: Clean some known patterns (optional but helps)
dt[, location_clean := gsub("^(Republic|Kingdom|Commonwealth|Democratic Republic|Principality|Federated States|State|United States|Islamic Republic|Portuguese|Union) of ", "", location)]
dt[, location_clean := gsub(" of the", "", location_clean)]
dt[, location_clean := trimws(location_clean)]

# Step 2: Use countrycode to assign ISO3 codes
dt[, iso3 := countrycode(location_clean, origin = "country.name", destination = "iso3c")]


# missing countries
dt[location=="Democratic Republic of the Congo", iso3 := "COD"]

dt[location=="USA", location := "United States"]

dt$location_clean <- NULL
fwrite(dt,file=paste0(wd_raw,"dt_sodium_powles_2013.csv"))
