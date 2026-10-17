# Diagnostic audit of b07d1a3 using the team's merged H-03 functions.
# Run: Rscript data/audit_h02.R app/qc.R . data/audit
# Supply a saved, pinned H-03 source path if app/qc.R is absent on this branch.
# Offset normalization below is IN MEMORY ONLY; no input CSV is changed.
args <- commandArgs(trailingOnly=TRUE)
if (length(args) != 3L) stop("Usage: Rscript data/audit_h02.R <qc.R> <repository> <output-directory>")
source(args[1]); repo <- args[2]; out <- args[3]
dir.create(out,recursive=TRUE,showWarnings=FALSE)
stopifnot(is.na(parse_ts('2026-09-21T07:00:00-0400')),
          !is.na(parse_ts('2026-09-21T07:00:00-04:00')))
# Test H-03's existing arithmetic, including both run rules, before scenario analysis.
k <- p_chart(c(4,6,5,3,7),rep(100,5)); stopifnot(abs(k$p_bar-.05)<1e-12,abs(k$data$ucl[1]-.115383)<1e-6)
stopifnot(all(is.na(p_chart(rep(0,3),rep(100,3))$data$rule1)))
stopifnot(identical(which(run_flags(rep(1,9),0)),8:9))
all_charts <- list(); all_counts <- list(); all_loader <- list(); all_station <- list(); all_minutes <- list()
for (name in c('baseline','planted_shift','edge_case')) {
 raw <- read_scenario(file.path(repo,'data',paste0(name,'.csv')))
 original <- validate_scenario(raw)
 cat(name,'original clean counts:',nrow(original$status),nrow(original$attempts),nrow(original$tasks),'issues:',nrow(original$issues),'\n')
 all_loader[[name]] <- data.frame(scenario=name,version='original',status=nrow(original$status),attempts=nrow(original$attempts),tasks=nrow(original$tasks),issues=nrow(original$issues))
 # Diagnostic normalization only. It does not modify the source CSV or generator.
 for (col in c('timestamp','assigned_at','arrived_at','completed_at')) {
  raw[[col]] <- sub('([+-][0-9]{2})([0-9]{2})$','\\1:\\2',raw[[col]])
 }
 clean <- validate_scenario(raw)
 cat(name,'normalized clean counts:',nrow(clean$status),nrow(clean$attempts),nrow(clean$tasks),'issues:',nrow(clean$issues),'\n')
 all_loader[[paste0(name,'_normalized')]] <- data.frame(scenario=name,version='offset normalized in memory',status=nrow(clean$status),attempts=nrow(clean$attempts),tasks=nrow(clean$tasks),issues=nrow(clean$issues))
 write.csv(clean$issues,file.path(out,paste0(name,'_issues.csv')),row.names=FALSE)
 dates <- sort(unique(format(clean$status$timestamp,'%Y-%m-%d',tz='America/New_York')))
 att <- clean$attempts
 date <- format(att$timestamp,'%Y-%m-%d',tz='America/New_York'); hour <- as.integer(format(att$timestamp,'%H',tz='America/New_York'))
 rush <- att[hour>=7 & hour<10,]; rush$date <- date[hour>=7 & hour<10]
 daily <- do.call(rbind,lapply(dates,function(d) {
  a <- rush[rush$date==d,]
  data.frame(scenario=name,day=match(d,dates),date=d,rent_n=sum(a$attempt_type=='rent'),rent_fail=sum(a$attempt_type=='rent' & !a$success),return_n=sum(a$attempt_type=='return'),return_fail=sum(a$attempt_type=='return' & !a$success))
 }))
 all_counts[[name]] <- daily
 for (base in if(name=='edge_case') 1 else c(10,20)) {
  for (typ in c('rent','return')) {
   chart <- p_chart(daily[[paste0(typ,'_fail')]],daily[[paste0(typ,'_n')]],seq_len(base))
   result <- cbind(scenario=name,type=typ,baseline_days=base,date=dates,chart$data)
   all_charts[[paste(name,base,typ)]] <- result
   cat(name,typ,'baseline',base,'pbar',chart$p_bar,'rule1',paste(which(chart$data$rule1),collapse=','),'rule4',paste(which(chart$data$rule4),collapse=','),'\n')
  }
 }
 station <- aggregate(as.integer(!rush$success),list(date=rush$date,station_id=rush$station_id,type=rush$attempt_type),sum)
 names(station)[4]<-'failures';station$scenario<-name;all_station[[name]]<-station
 mins <- do.call(rbind,lapply(dates,function(d) {
  # Use H-03 grid and summaries, with the same fixed station set on every day.
  g <- build_grid(clean$status,clean$stations,d)
  cbind(scenario=name,day=match(d,dates),date=d,grid_window_counts(g),summarise_minutes(g))
 }))
 all_minutes[[name]]<-mins
 for (base in if(name=='edge_case') 1 else c(10,20)) {
  ch<-imr_chart(100*mins$either_share,seq_len(base))
  write.csv(cbind(date=dates,ch$data),file.path(out,paste0(name,'_imr_base',base,'.csv')),row.names=FALSE)
  cat(name,'I-MR baseline',base,'rule1',paste(which(ch$data$rule1),collapse=','),'rule4',paste(which(ch$data$rule4),collapse=','),'MR',paste(which(ch$data$mr_signal),collapse=','),'\n')
 }
 if(name=='edge_case') write.csv(unusable_summary(build_grid(clean$status,clean$stations,dates[1])),file.path(out,'edge_station_minutes.csv'),row.names=FALSE)
}
write.csv(do.call(rbind,all_charts),file.path(out,'p_charts.csv'),row.names=FALSE)
write.csv(do.call(rbind,all_counts),file.path(out,'daily_attempts.csv'),row.names=FALSE)
write.csv(do.call(rbind,all_loader),file.path(out,'loader_counts.csv'),row.names=FALSE)
write.csv(do.call(rbind,all_station),file.path(out,'station_failures.csv'),row.names=FALSE)
write.csv(do.call(rbind,all_minutes),file.path(out,'daily_minutes.csv'),row.names=FALSE)
