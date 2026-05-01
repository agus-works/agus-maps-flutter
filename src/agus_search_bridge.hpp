#pragma once

#include "agus_maps_flutter.h"

#include "map/everywhere_search_params.hpp"
#include "map/framework.hpp"
#include "map/viewport_search_params.hpp"

#include "geometry/mercator.hpp"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace agus_search_bridge
{
namespace
{
enum class SearchStatus : int32_t
{
  Idle = 0,
  Running = 1,
  Completed = 2,
  Cancelled = 3,
  Error = 4,
};

struct SearchRow
{
  int32_t index = -1;
  int32_t resultType = 0;
  bool isSuggestion = false;
  bool hasPoint = false;
  std::string title;
  std::string subtitle;
  std::string address;
  std::string suggestion;
  double lat = 0.0;
  double lon = 0.0;
};

struct SearchState
{
  std::mutex mutex;
  int32_t generation = 0;
  SearchStatus status = SearchStatus::Idle;
  search::Results nativeResults;
  std::vector<SearchRow> rows;
};

SearchState g_searchState;

char * CopyCString(std::string const & value)
{
  auto * out = static_cast<char *>(std::malloc(value.size() + 1));
  if (!out)
    return nullptr;
  std::memcpy(out, value.c_str(), value.size() + 1);
  return out;
}

int32_t ResultTypeToInt(search::Result::Type type)
{
  switch (type)
  {
  case search::Result::Type::Feature: return 0;
  case search::Result::Type::LatLon: return 1;
  case search::Result::Type::PureSuggest: return 2;
  case search::Result::Type::SuggestFromFeature: return 3;
  case search::Result::Type::Postcode: return 4;
  }

  return 0;
}

SearchRow BuildSearchRow(search::Result const & result, int32_t index)
{
  SearchRow row;
  row.index = index;
  row.resultType = ResultTypeToInt(result.GetResultType());
  row.isSuggestion = result.IsSuggest();
  row.hasPoint = result.HasPoint();
  row.title = result.GetString();
  row.address = result.GetAddress();

  if (row.title.empty())
    row.title = result.GetLocalizedFeatureType();

  if (row.isSuggestion)
  {
    row.suggestion = result.GetSuggestionString();
    row.subtitle = "Suggestion";
  }
  else
  {
    row.subtitle = result.GetFeatureDescription();
    if (row.subtitle.empty())
      row.subtitle = result.GetLocalizedFeatureType();
  }

  if (row.hasPoint)
  {
    auto const latLon = mercator::ToLatLon(result.GetFeatureCenter());
    row.lat = latLon.m_lat;
    row.lon = latLon.m_lon;
  }

  return row;
}

std::vector<SearchRow> BuildRows(search::Results const & results)
{
  std::vector<SearchRow> rows;
  rows.reserve(results.GetCount());
  for (size_t i = 0; i < results.GetCount(); ++i)
    rows.push_back(BuildSearchRow(results[i], static_cast<int32_t>(i)));
  return rows;
}

void StoreResults(int32_t generation, search::Results results)
{
  std::lock_guard<std::mutex> lock(g_searchState.mutex);
  if (generation != g_searchState.generation)
    return;

  if (!results.IsEndMarker() || results.GetCount() > 0 || results.IsEndedNormal())
  {
    g_searchState.rows = BuildRows(results);
    g_searchState.nativeResults = std::move(results);
  }

  if (g_searchState.nativeResults.IsEndMarker())
  {
    g_searchState.status = g_searchState.nativeResults.IsEndedCancelled() ? SearchStatus::Cancelled
                                                                          : SearchStatus::Completed;
  }
  else
  {
    g_searchState.status = SearchStatus::Running;
  }
}

void MarkStatus(int32_t generation, SearchStatus status)
{
  std::lock_guard<std::mutex> lock(g_searchState.mutex);
  if (generation == g_searchState.generation)
    g_searchState.status = status;
}
}  // namespace

static inline int32_t StartSearch(Framework * framework, char const * query, char const * locale, int32_t interactive,
                                  int32_t isCategory)
{
  if (!framework || !query || query[0] == '\0')
    return -1;

  std::string queryString(query);
  std::string localeString = (locale && locale[0] != '\0') ? locale : "en";

  int32_t generation = 0;
  {
    std::lock_guard<std::mutex> lock(g_searchState.mutex);
    generation = ++g_searchState.generation;
    g_searchState.status = SearchStatus::Running;
    g_searchState.nativeResults.Clear();
    g_searchState.rows.clear();
  }

  try
  {
    if (interactive != 0)
    {
      search::ViewportSearchParams viewportParams{queryString,
                                                  localeString,
                                                  {},
                                                  isCategory != 0,
                                                  {},
                                                  {}};
      framework->GetSearchAPI().SearchInViewport(std::move(viewportParams));
    }

    search::EverywhereSearchParams everywhereParams{
        std::move(queryString),
        std::move(localeString),
        {},
        isCategory != 0,
        [generation, interactive, framework](search::Results results,
                                             std::vector<search::ProductInfo> /* productInfo */) mutable
        {
          bool const endedNormally = results.IsEndMarker() && results.IsEndedNormal();
          StoreResults(generation, std::move(results));
          if (interactive != 0 && endedNormally && framework)
            framework->GetSearchAPI().PokeSearchInViewport();
        }};

    if (!framework->GetSearchAPI().SearchEverywhere(std::move(everywhereParams)))
    {
      MarkStatus(generation, SearchStatus::Completed);
      return generation;
    }
  }
  catch (...)
  {
    MarkStatus(generation, SearchStatus::Error);
    return -2;
  }

  return generation;
}

static inline AgusSearchResults * CopyResults()
{
  std::lock_guard<std::mutex> lock(g_searchState.mutex);

  auto * snapshot = static_cast<AgusSearchResults *>(std::calloc(1, sizeof(AgusSearchResults)));
  if (!snapshot)
    return nullptr;

  snapshot->generation = g_searchState.generation;
  snapshot->status = static_cast<int32_t>(g_searchState.status);
  snapshot->result_count = static_cast<int32_t>(g_searchState.rows.size());

  if (g_searchState.rows.empty())
    return snapshot;

  snapshot->results = static_cast<AgusSearchResult *>(std::calloc(g_searchState.rows.size(), sizeof(AgusSearchResult)));
  if (!snapshot->results)
  {
    snapshot->result_count = 0;
    return snapshot;
  }

  for (size_t i = 0; i < g_searchState.rows.size(); ++i)
  {
    auto const & row = g_searchState.rows[i];
    auto & out = snapshot->results[i];
    out.index = row.index;
    out.result_type = row.resultType;
    out.is_suggestion = row.isSuggestion ? 1 : 0;
    out.has_point = row.hasPoint ? 1 : 0;
    out.title = CopyCString(row.title);
    out.subtitle = CopyCString(row.subtitle);
    out.address = CopyCString(row.address);
    out.suggestion = CopyCString(row.suggestion);
    out.lat = row.lat;
    out.lon = row.lon;
  }

  return snapshot;
}

static inline void FreeResults(AgusSearchResults * data)
{
  if (!data)
    return;

  if (data->results)
  {
    for (int32_t i = 0; i < data->result_count; ++i)
    {
      auto & result = data->results[i];
      std::free(const_cast<char *>(result.title));
      std::free(const_cast<char *>(result.subtitle));
      std::free(const_cast<char *>(result.address));
      std::free(const_cast<char *>(result.suggestion));
    }
    std::free(data->results);
  }

  std::free(data);
}

static inline int32_t ShowResult(Framework * framework, int32_t index)
{
  if (!framework)
    return -1;

  std::unique_ptr<search::Result> selectedResult;
  {
    std::lock_guard<std::mutex> lock(g_searchState.mutex);
    if (index < 0 || static_cast<size_t>(index) >= g_searchState.nativeResults.GetCount())
      return -2;

    auto const & result = g_searchState.nativeResults[static_cast<size_t>(index)];
    if (result.IsSuggest())
      return 0;

    selectedResult = std::make_unique<search::Result>(result);
  }

  try
  {
    framework->ShowSearchResult(*selectedResult);
  }
  catch (...)
  {
    return -3;
  }

  return 1;
}

static inline void Cancel(Framework * framework)
{
  if (framework)
    framework->GetSearchAPI().CancelAllSearches();

  std::lock_guard<std::mutex> lock(g_searchState.mutex);
  ++g_searchState.generation;
  g_searchState.status = SearchStatus::Idle;
  g_searchState.nativeResults.Clear();
  g_searchState.rows.clear();
}
}  // namespace agus_search_bridge
