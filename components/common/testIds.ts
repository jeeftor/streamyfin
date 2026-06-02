import type { BaseItemDto } from "@jellyfin/sdk/lib/generated-client/models";
import type {
  MovieResult,
  PersonResult,
  TvResult,
} from "@/utils/jellyseerr/server/models/Search";

export const getJellyfinItemTestId = (
  item: BaseItemDto,
): string | undefined => {
  if (!item.Id) return undefined;

  if (
    item.Type === "CollectionFolder" ||
    item.Type === "UserView" ||
    "CollectionType" in item
  ) {
    return `library-item-${item.Id}`;
  }

  return `media-item-${item.Id}`;
};

export const getJellyseerrItemTestId = (
  item: MovieResult | TvResult | PersonResult | undefined,
): string | undefined => {
  if (!item?.id) return undefined;

  return `jellyseerr-item-${item.mediaType}-${item.id}`;
};
