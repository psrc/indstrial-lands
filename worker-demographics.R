library(magrittr)
library(psrccensus)
library(dplyr)
library(srvyr)
library(fredr)
library(lubridate)
library(openxlsx)
library(tidyr)

# references --------------------------------------------------------
dyear <- 2020
refyear <- year(Sys.Date()) - year(Sys.Date()) %% 10
pums_vars <- c("PRACE","ED_ATTAIN","COW","PINCP","MI_JOBSECTOR") #,"NAICSP02","NAICSP07")


# helper functions --------------------------------------------------

inflation_adjust <- function(dyear, refyear){
  x <- fredr(series_id = "DPCERG3A086NBEA",                                                        # Requires FRED key in .Renviron, see fredr documentation
             observation_start = as_date(paste0(dyear,"-01-01")),
             observation_end = as_date(paste0(refyear,"-01-01")))
  factor <- last(x$value) / first(x$value)
  return(factor)
}

recode_vars <- function(data){
  data %<>% mutate(PINCP=case_when(!is.na(PINCP) ~PINCP * pce_ftr)) %>%                            # Apply multi-survey inflation adjustment
            mutate(PINCP_BIN:=factor(case_when(PINCP <  25000 ~"Under $25,000",                    # Custom income bins
                                               PINCP <  50000 ~"$25,000-$49,999",
                                               PINCP <  75000 ~"$50,000-$74,999",
                                               PINCP < 100000 ~"$75,000-$99,999",
                                               PINCP >=100000 ~"$100,000 or more",
                                               !is.na(PINCP)  ~"Else / Prefer not to answer"),
                                     levels=c("Under $25,000",
                                              "$25,000-$49,999",
                                              "$50,000-$74,999",
                                              "$75,000-$99,999",
                                              "$100,000 or more",
                                              "Else / Prefer not to answer")))
}

# psrc_mi_jobsector <- function(so){                                                               # Use with NAICS\\d+ fields above in case MI_JOBSECTOR is all NA 
#   so %<>% mutate(NAICSP02=as.character(NAICSP02), NAICSP07=as.character(NAICSP07)) %>%
#     mutate(NAICSP=coalesce(NAICSP07,NAICSP02)) %>%
#     mutate(MI_JOBSECTOR:=factor(case_when(grepl("^221|^45411|^5121|^515|^517|^5616|^56173|^562|^6242|^8113|^8114|^8123",
#                                                 as.character(NAICSP))                 ~"Other Industrial",
#                                           grepl("^42", as.character(NAICSP))     ~"Warehousing & Wholesale",
#                                           grepl("^48|^49", as.character(NAICSP)) ~"Transportation, Distribution & Logistics (TDL)",
#                                           grepl("^23", as.character(NAICSP))     ~"Construction",
#                                           grepl("^33|^3M", as.character(NAICSP)) ~"Manufacturing",
#                                           !is.na(NAICSP)                         ~ NA_character_),
#                                 levels=c("Construction","Manufacturing","Warehousing & Wholesale",
#                                          "Transportation, Distribution & Logistics (TDL)","Other Industrial")))
#   return(so)
# }

combined_counts <- function(data, group_var){                                                      # Results calculated separately for counties & region to preserve detail
  rs_reg <- psrc_pums_count(pums_data, group_vars=c("industrial", group_var), incl_na=FALSE)       # -- combined afterward
  rs_all <- psrc_pums_count(data, group_vars=c("COUNTY", "industrial", group_var), incl_na=FALSE) %>% 
    filter(COUNTY!="Region") %>% rbind(rs_reg) %>% 
    mutate(COUNTY=factor(COUNTY,levels=c("King","Kitsap","Pierce","Snohomish","Region")))
  return(rs_all)
}

combined_median <- function(data, targetvar){
  rs_reg <- psrc_pums_median(data, targetvar, group_vars=c("industrial"), incl_na=FALSE)
  rs_all <- psrc_pums_median(data, targetvar, group_vars=c("COUNTY", "industrial"), incl_na=FALSE) %>% 
    filter(COUNTY!="Region") %>% rbind(rs_reg) %>% 
    mutate(COUNTY=factor(COUNTY,levels=c("King","Kitsap","Pierce","Snohomish","Region")))
  return(rs_all)
}

xtabber <- function(data, stat_wanted){
  wanteds <- paste0(stat_wanted, c("","_moe"))                                                     # i.e. count or median
  key_var <- if(!grepl("_median", stat_wanted)){
    grep("^PRACE$|^ED_ATTAIN$|^PINCP_BIN$", colnames(data), value=TRUE)
  }else{NULL}
  measure_vars <- grep(paste0(c("count","share","PINCP_median"), rep(c("","_moe"),3),collapse="$|^"), 
                       colnames(data), value=TRUE)
  rt <- NULL
  rt <- data %>% select(!DATA_YEAR) %>% pivot_longer(cols=all_of(measure_vars), names_to="var_name") # Long format to prep for xtab
  rt %<>% filter(var_name %in% wanteds) %>% mutate(value=replace_na(value,0))
  rt <- if(any(grepl("^MI_JOBSECTOR$", colnames(data)))){                                          # Industrial sectors are columns in these xtabs  
    if(length(key_var)>0){
     pivot_wider(rt, id_cols={{key_var}}, names_from=c(MI_JOBSECTOR, var_name), 
                 values_from="value", names_vary="slowest")                                        # 'slowest' associates value and MOE together
    }else{
      pivot_wider(rt, names_from=c(MI_JOBSECTOR, var_name), values_from="value", 
                  names_vary="slowest")
    }
  }else if(!all(data$COUNTY=="Region")){                                                           # Counties/Region are columns in these xtabs   
    if(length(key_var)>0){
       pivot_wider(rt, id_cols=c(industrial, {{key_var}}), names_from=c(COUNTY, var_name), 
                   values_from="value", names_vary="slowest")
    }else{
       pivot_wider(rt, id_cols=industrial, names_from=c(COUNTY, var_name), values_from="value", 
                   names_vary="slowest")
    }
  }
  return(rt)
}

# main script -------------------------------------------------------

pce_ftr <- inflation_adjust(dyear, refyear)
#wd <- getwd()
pums_data <- get_psrc_pums(5, dyear, "p", pums_vars) #, dir=wd)                                    # Obtain the data; dir option if PUMS .gz files are in-hand
#pums_data %<>% psrc_mi_jobsector()
pums_data %<>% filter((!grepl("^Unemployed", COW) & !is.na(COW))) %>% recode_vars() %>%            # Apply inflation adjustment, custom fields
  mutate(industrial=factor(if_else(!is.na(MI_JOBSECTOR), "Industrial", "Non-Industrial")))

deep_pocket <- list()                                                                              # Calculate estimates; counts & shares both included
deep_pocket[[1]] <- combined_counts(pums_data, "PRACE")
deep_pocket[[2]] <- combined_counts(pums_data, "ED_ATTAIN")
deep_pocket[[3]] <- combined_counts(pums_data, "PINCP_BIN")
deep_pocket[[4]] <- psrc_pums_count(pums_data, group_vars=c("MI_JOBSECTOR","PRACE"), incl_na=FALSE)
deep_pocket[[5]] <- psrc_pums_count(pums_data, group_vars=c("MI_JOBSECTOR","ED_ATTAIN"), incl_na=FALSE)
deep_pocket[[6]] <- psrc_pums_count(pums_data, group_vars=c("MI_JOBSECTOR","PINCP_BIN"), incl_na=FALSE)
deep_pocket[[7]] <- combined_median(pums_data, "PINCP")
deep_pocket[[8]] <- psrc_pums_median(pums_data, "PINCP", group_vars="MI_JOBSECTOR", incl_na=FALSE)

xtab_pocket <- list()                                                                              # Counts & shares in separate xtabs
xtab_pocket[1:3]   <- mapply(xtabber, deep_pocket[1:3], "share", SIMPLIFY=FALSE)
xtab_pocket[4:6]   <- mapply(xtabber, deep_pocket[1:3], "count", SIMPLIFY=FALSE)
xtab_pocket[7:9]   <- mapply(xtabber, deep_pocket[4:6], "share", SIMPLIFY=FALSE)
xtab_pocket[10:12] <- mapply(xtabber, deep_pocket[4:6], "count", SIMPLIFY=FALSE)
xtab_pocket[13:14] <- mapply(xtabber, deep_pocket[7:8], "PINCP_median", SIMPLIFY=FALSE)
names(xtab_pocket) <- paste0("Sheet",1:length(xtab_pocket))                       
write.xlsx(xtab_pocket, file = paste0("IndLa_worker_demographics_", dyear,".xlsx"))                # Output saved to multi-sheet file in working directory
