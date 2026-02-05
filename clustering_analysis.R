# 1. Load required packages
library(tidyverse)
install.packages("fastDummies")
library(fastDummies)
library(cluster)
library(factoextra)

# 2. Read and merge the data
# These two filtered datasets were exported from Power BI 
# after we applied our data cleaning and modeling steps.

netflix <- read.csv("Filtered_Netflix.csv")
tomatoes <- read.csv("Filtered_Rotten_Tomatoes.csv")
merged <- inner_join(netflix, tomatoes, by = "Type_Title")

# 3. Data cleaning and variable preparation
merged_selected <- merged |>
  mutate(
    IMDb.Votes = as.numeric(IMDb.Votes),
    Awards.Received = replace_na(as.numeric(Awards.Received), 0),
    IMDb.Votes = log10(IMDb.Votes + 1)
  ) |>
  mutate(across(c(Country, Genre, Languages), ~ na_if(str_trim(.), ""))) |>
  filter(if_all(c(Country, Genre, Languages), ~ !is.na(.)))

# 4. Process countries and genres
top_genres <- merged_selected |>
  separate_rows(Genre, sep = ",\\s*") |>
  count(Genre, sort = TRUE) |>
  slice_head(n = 5) |> pull(Genre)

top_countries <- merged_selected |>
  separate_rows(Country, sep = ",\\s*") |>
  count(Country, sort = TRUE) |>
  slice_head(n = 5) |> pull(Country)



merged_selected <- merged_selected |>
  mutate(
    Main_Genre = map_chr(str_split(Genre, ",\\s*"), ~ {
      matched <- intersect(., top_genres)
      if (length(matched) > 0) matched[1] else "Other"
    }),
    Main_Country = map_chr(str_split(Country, ",\\s*"), ~ {
      matched <- intersect(., top_countries)
      if (length(matched) > 0) matched[1] else "Other"
    })
  )

# 5. Prepare clustering data (including categorical encoding)
cluster_data <- merged_selected |>
  select(IMDb.Votes, Awards.Received, Main_Country, Main_Genre) |>
  dummy_cols(select_columns = c("Main_Country", "Main_Genre"),
             remove_selected_columns = TRUE, remove_first_dummy = TRUE)

# 6. Remove missing values and standardize
valid_rows <- complete.cases(cluster_data)
cluster_data_valid <- cluster_data[valid_rows, ]
scaled_data <- scale(cluster_data_valid)



# 7. Use Elbow method to determine the optimal number of clusters (k)
fviz_nbclust(scaled_data, kmeans, method = "wss") +
  geom_vline(xintercept = 3, linetype = 2) + 
  labs(title = "Elbow Method to Determine Optimal Clusters",
       x = "Number of Clusters K",
       y = "Total Within-Cluster Sum of Squares") +
  theme_minimal()

# 8. Perform k-means clustering ( K = 3)
set.seed(2)
k <- 3
kmeans_result <- kmeans(scaled_data, centers = k, nstart = 25)

# 9. Add cluster results back to the original data
merged_valid <- merged_selected[valid_rows, ]
merged_valid$Cluster <- as.factor(kmeans_result$cluster)


# 10. Create additional statistical summaries for each cluster
cluster_top3_genre <- merged_valid |>
  group_by(Cluster, Main_Genre) |>
  summarise(Count = n(), .groups = "drop") |>
  arrange(Cluster, desc(Count)) |>
  group_by(Cluster) |>
  slice_head(n = 3) |>
  summarise(Top3_Genres = paste(Main_Genre, collapse = ", "), .groups = "drop")


cluster_summary <- merged_valid |>
  group_by(Cluster)|>
  summarise(
    Count = n(),
    Avg_IMDb_Votes = round(mean(IMDb.Votes, na.rm = TRUE), 2),
    Avg_Awards_Received = round(mean(Awards.Received, na.rm = TRUE), 2),
    Top_Country = names(sort(table(Main_Country), decreasing = TRUE))[1]
  )


cluster_summary_combined <- left_join(cluster_summary, cluster_top3_genre, by = "Cluster")

# View results
print(cluster_summary_combined)

# 11. Export results for further visualization in Power BI

write.csv(merged_valid, file = "Final_Cluster.csv", row.names = FALSE)







