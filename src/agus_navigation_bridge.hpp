#pragma once

#include "agus_maps_flutter.h"

#include "map/framework.hpp"
#include "map/routing_mark.hpp"
#include "platform/distance.hpp"
#include "platform/measurement_utils.hpp"
#include "platform/settings.hpp"
#include "routing/following_info.hpp"
#include "routing/router.hpp"
#include "routing/routing_callbacks.hpp"
#include "routing/routing_options.hpp"
#include "routing/speed_camera_manager.hpp"

#include "geometry/mercator.hpp"

#include <cstdlib>
#include <cstring>
#include <string>
#include <utility>

namespace agus::navigation
{
inline char * CopyString(std::string const & value)
{
  auto const size = value.size();
  auto * out = static_cast<char *>(std::malloc(size + 1));
  if (out == nullptr)
    return nullptr;
  if (size > 0)
    std::memcpy(out, value.data(), size);
  out[size] = '\0';
  return out;
}

inline void FreeString(char const * value)
{
  std::free(const_cast<char *>(value));
}

inline bool IsValidRouterType(int32_t routerType)
{
  return routerType >= 0 &&
         routerType < static_cast<int32_t>(routing::RouterType::Count);
}

inline bool IsValidRouteMarkType(int32_t markType)
{
  return markType >= static_cast<int32_t>(RouteMarkType::Start) &&
         markType <= static_cast<int32_t>(RouteMarkType::Finish);
}

inline measurement_utils::Units UnitsFromInt(int32_t units)
{
  return units == static_cast<int32_t>(measurement_utils::Units::Imperial)
             ? measurement_utils::Units::Imperial
             : measurement_utils::Units::Metric;
}

inline int32_t GetMeasurementUnits()
{
  return static_cast<int32_t>(measurement_utils::GetMeasurementUnits());
}

inline void SetMeasurementUnits(Framework * framework, int32_t unitsValue)
{
  auto const units = UnitsFromInt(unitsValue);
  settings::Set(settings::kMeasurementUnits, units);
  if (framework != nullptr)
    framework->GetRoutingManager().SetTurnNotificationsUnits(units);
}

inline int32_t GetAvoidRoutingOptions()
{
  return static_cast<int32_t>(
      routing::RoutingOptions::LoadCarOptionsFromSettings().GetOptions());
}

inline void SetAvoidRoutingOptions(int32_t mask)
{
  auto const allowed = static_cast<int32_t>(routing::RoutingOptions::Road::Toll) |
                       static_cast<int32_t>(routing::RoutingOptions::Road::Motorway) |
                       static_cast<int32_t>(routing::RoutingOptions::Road::Ferry) |
                       static_cast<int32_t>(routing::RoutingOptions::Road::Dirty);
  routing::RoutingOptions::SaveCarOptionsToSettings(
      routing::RoutingOptions(static_cast<routing::RoutingOptions::RoadType>(mask & allowed)));
}

inline void EnsureRoutingCallbacks(Framework * framework)
{
  if (framework == nullptr)
    return;
  auto & manager = framework->GetRoutingManager();
  manager.SetRouteBuildingListener(
      [](routing::RouterResultCode, storage::CountriesSet const &) {});
  manager.SetRouteProgressListener([](float) {});
}

inline int32_t SetRouter(Framework * framework, int32_t routerType)
{
  if (framework == nullptr)
    return -1;
  if (!IsValidRouterType(routerType))
    return -2;

  EnsureRoutingCallbacks(framework);
  framework->GetRoutingManager().SetRouter(
      static_cast<routing::RouterType>(routerType));
  return 1;
}

inline int32_t GetRouter(Framework * framework)
{
  if (framework == nullptr)
    return -1;
  return static_cast<int32_t>(framework->GetRoutingManager().GetRouter());
}

inline int32_t AddRoutePoint(Framework * framework, int32_t markType,
                             char const * title, char const * subtitle,
                             double lat, double lon,
                             int32_t intermediateIndex, int32_t isMyPosition,
                             int32_t reorderIntermediatePoints)
{
  if (framework == nullptr)
    return -1;
  if (!IsValidRouteMarkType(markType))
    return -2;

  EnsureRoutingCallbacks(framework);
  RouteMarkData data;
  data.m_title = title == nullptr ? std::string() : std::string(title);
  data.m_subTitle = subtitle == nullptr ? std::string() : std::string(subtitle);
  data.m_pointType = static_cast<RouteMarkType>(markType);
  data.m_intermediateIndex = intermediateIndex < 0
                                 ? 0
                                 : static_cast<size_t>(intermediateIndex);
  data.m_isMyPosition = isMyPosition != 0;
  data.m_position = mercator::FromLatLon(lat, lon);
  framework->GetRoutingManager().AddRoutePoint(
      std::move(data), reorderIntermediatePoints != 0);
  return 1;
}

inline void RemoveRoutePoint(Framework * framework, int32_t markType,
                             int32_t intermediateIndex)
{
  if (framework == nullptr || !IsValidRouteMarkType(markType))
    return;
  framework->GetRoutingManager().RemoveRoutePoint(
      static_cast<RouteMarkType>(markType),
      intermediateIndex < 0 ? 0 : static_cast<size_t>(intermediateIndex));
}

inline void ClearRoutePoints(Framework * framework)
{
  if (framework != nullptr)
    framework->GetRoutingManager().RemoveRoutePoints();
}

inline int32_t BuildRoute(Framework * framework)
{
  if (framework == nullptr)
    return -1;
  EnsureRoutingCallbacks(framework);
  framework->GetRoutingManager().BuildRoute();
  return 1;
}

inline int32_t FollowRoute(Framework * framework)
{
  if (framework == nullptr)
    return -1;
  EnsureRoutingCallbacks(framework);
  framework->GetRoutingManager().FollowRoute();
  return framework->GetRoutingManager().IsRoutingFollowing() ? 1 : 0;
}

inline void CloseRoute(Framework * framework, int32_t removeRoutePoints)
{
  if (framework != nullptr)
    framework->GetRoutingManager().CloseRouting(removeRoutePoints != 0);
}

inline int32_t IsActive(Framework * framework)
{
  return framework != nullptr && framework->GetRoutingManager().IsRoutingActive();
}

inline int32_t IsBuilt(Framework * framework)
{
  return framework != nullptr && framework->GetRoutingManager().IsRouteBuilt();
}

inline int32_t IsBuilding(Framework * framework)
{
  return framework != nullptr && framework->GetRoutingManager().IsRouteBuilding();
}

inline int32_t IsFollowing(Framework * framework)
{
  return framework != nullptr && framework->GetRoutingManager().IsRoutingFollowing();
}

inline void FillDistance(platform::Distance const & distance, double & value,
                         int32_t & units)
{
  value = distance.GetDistance();
  units = static_cast<int32_t>(distance.GetUnits());
}

inline AgusNavigationStatus * CopyStatus(Framework * framework)
{
  auto * status = static_cast<AgusNavigationStatus *>(
      std::calloc(1, sizeof(AgusNavigationStatus)));
  if (status == nullptr)
    return nullptr;

  status->router_type = framework == nullptr
                            ? -1
                            : static_cast<int32_t>(
                                  framework->GetRoutingManager().GetRouter());
  status->route_session_state =
      static_cast<int32_t>(routing::SessionState::NoValidRoute);
  status->turn = 0;
  status->next_turn = 0;
  status->pedestrian_turn = 0;
  status->speed_limit_mps = -1.0;

  if (framework == nullptr)
    return status;

  auto & manager = framework->GetRoutingManager();
  status->is_active = manager.IsRoutingActive() ? 1 : 0;
  status->is_built = manager.IsRouteBuilt() ? 1 : 0;
  status->is_building = manager.IsRouteBuilding() ? 1 : 0;
  status->is_following = manager.IsRoutingFollowing() ? 1 : 0;
  status->is_valid = manager.IsRouteValid() ? 1 : 0;

  if (!manager.IsRoutingActive())
    return status;

  routing::FollowingInfo info;
  manager.GetRouteFollowingInfo(info);
  status->route_session_state = static_cast<int32_t>(info.m_routingSessionState);
  if (!info.IsValid())
    return status;

  status->has_following_info = 1;
  status->turn = static_cast<int32_t>(info.m_turn);
  status->next_turn = static_cast<int32_t>(info.m_nextTurn);
  status->pedestrian_turn = static_cast<int32_t>(info.m_pedestrianTurn);
  status->exit_number = static_cast<int32_t>(info.m_exitNum);
  status->total_time_seconds = info.m_time;
  status->completion_percent = info.m_completionPercent;
  status->speed_limit_mps = info.m_speedLimitMps;
  status->time_to_next_stop_seconds = info.m_timeToNextStop;
  status->index_of_next_stop = info.m_indexOfNextStop;
  FillDistance(info.m_distToTarget, status->distance_to_target,
               status->distance_to_target_units);
  FillDistance(info.m_distToTurn, status->distance_to_turn,
               status->distance_to_turn_units);
  FillDistance(info.m_distToNextStop, status->distance_to_next_stop,
               status->distance_to_next_stop_units);
  status->current_street = CopyString(info.m_currentStreetName);
  status->next_street = CopyString(info.m_nextStreetName);
  status->next_next_street = CopyString(info.m_nextNextStreetName);
  return status;
}

inline void FreeStatus(AgusNavigationStatus * status)
{
  if (status == nullptr)
    return;
  FreeString(status->current_street);
  FreeString(status->next_street);
  FreeString(status->next_next_street);
  std::free(status);
}

inline void SetTurnNotificationsEnabled(Framework * framework, int32_t enabled)
{
  if (framework != nullptr)
    framework->GetRoutingManager().EnableTurnNotifications(enabled != 0);
}

inline int32_t GetTurnNotificationsEnabled(Framework * framework)
{
  return framework != nullptr &&
         framework->GetRoutingManager().AreTurnNotificationsEnabled();
}

inline void SetTurnNotificationsLocale(Framework * framework, char const * locale)
{
  if (framework != nullptr)
  {
    framework->GetRoutingManager().SetTurnNotificationsLocale(
        locale == nullptr ? std::string() : std::string(locale));
  }
}

inline routing::SpeedCameraManagerMode SpeedCameraModeFromInt(int32_t mode)
{
  if (mode == static_cast<int32_t>(routing::SpeedCameraManagerMode::Always))
    return routing::SpeedCameraManagerMode::Always;
  if (mode == static_cast<int32_t>(routing::SpeedCameraManagerMode::Never))
    return routing::SpeedCameraManagerMode::Never;
  return routing::SpeedCameraManagerMode::Auto;
}

inline void SetSpeedCameraMode(Framework * framework, int32_t mode)
{
  if (framework != nullptr)
    framework->GetRoutingManager().GetSpeedCamManager().SetMode(
        SpeedCameraModeFromInt(mode));
}

inline int32_t GetSpeedCameraMode(Framework * framework)
{
  if (framework == nullptr)
    return static_cast<int32_t>(routing::SpeedCameraManagerMode::Auto);
  return static_cast<int32_t>(
      framework->GetRoutingManager().GetSpeedCamManager().GetMode());
}
}  // namespace agus::navigation