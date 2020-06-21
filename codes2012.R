install.packages("INLA", repos = "https://inla.r-inla-download.org/R/stable",
                 dep = TRUE)
library(SpatialEpi)
library(INLA)
library(sp)
library(leaflet)
require(spdep)
library(dplyr)
library(ggplot2)

load('DataWithRadon.RData')

#extract data
d <- d1[d1$Year==2012,]
d$Age_Adjusted_Rate <- as.numeric(d$Age_Adjusted_Rate)
d$Population <- as.numeric(d$Population)
d[is.na(d$Deaths),]$Population <- NA
d$Deaths <- as.numeric(d$Deaths)

#expected count
E <- d$Population*sum(d$Deaths, na.rm=TRUE)/sum(d$Population, na.rm=TRUE)
d$E <- E
d$SIR <- d$Deaths/d$E

#add to map
d <- as.data.frame(d)
rownames(d)<- d$id
map <- SpatialPolygonsDataFrame(pennLC$spatial.polygon, d, match.ID = TRUE)
head(map@data)

#mapping variable
######## raw count
l <- leaflet(map) %>% addTiles()
pal <- colorNumeric(palette = "YlOrRd", domain = map$Deaths)
l %>% addPolygons(color = "grey", weight = 1, fillColor = ~pal(Deaths),
                  fillOpacity = 0.8) %>%
    addLegend(pal = pal, values = ~Deaths, opacity = 0.8, title = "Deaths",
              position = "bottomright")

######## expected count
l <- leaflet(map) %>% addTiles()
pal <- colorNumeric(palette = "YlOrRd", domain = map$E)
l %>% addPolygons(color = "grey", weight = 1, fillColor = ~pal(E),
                  fillOpacity = 0.8) %>%
    addLegend(pal = pal, values = ~E, opacity = 0.8, title = "Expected",
              position = "bottomright")

######### SIR
l <- leaflet(map) %>% addTiles()
pal <- colorNumeric(palette = "YlOrRd", domain = map$SIR)
l %>% addPolygons(color = "grey", weight = 1, fillColor = ~pal(SIR),
                  fillOpacity = 0.8) %>%
    addLegend(pal = pal, values = ~SIR, opacity = 0.8, title = "SIR",
              position = "bottomright")

#neighborhood matrix
nb <- poly2nb(map)
head(nb)
nb2INLA("map.adj", nb)
g <- inla.read.graph(filename = "map.adj")

#inference using INLA
map$re_u <- 1:nrow(map@data)
map$re_v <- 1:nrow(map@data)

########### SIR
formula <- Deaths ~ smoking + Radon + f(re_u, model = "besag", graph = g) + f(re_v, model = "iid")
res <- inla(formula, family = "poisson", data = map@data[!is.na(E),], E=E,
            control.predictor = list(compute = TRUE))
summary(res)

marginal <- inla.smarginal(res$marginals.fixed$smoking)
marginal <- data.frame(marginal)
png('posterior distribution of smoking.png', res=300, width=1200, height=1000)
ggplot(marginal, aes(x = x, y = y)) + geom_line() +
    labs(x = expression(beta[1]), y = "Density") +
    geom_vline(xintercept = 0, col = "blue") + theme_bw() + 
    ggtitle('Posterior distribution of Beta1')
dev.off()

marginal <- inla.smarginal(res$marginals.fixed$Radon)
marginal <- data.frame(marginal)
png('posterior distribution of radon.png', res=300, width=1200, height=1000)
ggplot(marginal, aes(x = x, y = y)) + geom_line() +
    labs(x = expression(beta[2]), y = "Density") +
    geom_vline(xintercept = 0, col = "blue") + theme_bw() + 
    ggtitle('Posterior distribution of Beta2')
dev.off()


# mapping disease Risk
map$RR <- c(res$summary.fitted.values[, "mean"][1:11],NA, 
            res$summary.fitted.values[, "mean"][12:27],NA,
            res$summary.fitted.values[, "mean"][28:54],NA,
            res$summary.fitted.values[, "mean"][55:64])
map$LL <- c(res$summary.fitted.values[, "0.025quant"][1:11],NA, 
            res$summary.fitted.values[, "0.025quant"][12:27],NA,
            res$summary.fitted.values[, "0.025quant"][28:54],NA,
            res$summary.fitted.values[, "0.025quant"][55:64])
map$UL <- c(res$summary.fitted.values[, "0.975quant"][1:11],NA, 
            res$summary.fitted.values[, "0.975quant"][12:27],NA,
            res$summary.fitted.values[, "0.975quant"][28:54],NA,
            res$summary.fitted.values[, "0.975quant"][55:64])

pal <- colorNumeric(palette = "YlOrRd", domain = map$RR)
labels <- sprintf("<strong> %s </strong> <br/> Observed: %s <br/> Expected: %s <br/> Smokers proportion: %s <br/> Radon level: %s <br/> SIR: %s <br/> RR: %s (%s, %s)", map$County, map$Deaths,  round(map$E, 2),  map$smoking, round(map$Radon,2), (map$SIR, 2), round(map$RR, 2), round(map$LL, 2), round(map$UL, 2)) %>%
    lapply(htmltools::HTML)
leaflet(map) %>% addTiles() %>%
    addPolygons(color = "grey", weight = 1, fillColor = ~pal(RR),  fillOpacity = 0.8, highlightOptions = highlightOptions(weight = 4), label = labels, labelOptions = labelOptions(style = list("font-weight" = "normal", padding = "3px 8px"), textsize = "15px", direction = "auto")) %>%
    addLegend(pal = pal, values = ~RR, opacity = 0.8, title = "RR",
              position = "bottomright")

