# mushroomHunter
Help connect Pikimin players together, and call for help for mushroom hunter

## Firestore Schema (MVP)
- `users/{uid}`: displayName, friendCode, stars, honey, createdAt, updatedAt
- `rooms/{roomId}`: title, hostUid, hostName, hostStars, hostFriendCode, targetColor, targetAttribute, targetSize, location, note, minBid, status, maxPlayers, joinedCount, createdAt, updatedAt, lastSuccessfulRaidAt
- `rooms/{roomId}/attendees/{uid}`: uid, name, friendCode, stars, bidHoney, joinedAt, updatedAt
