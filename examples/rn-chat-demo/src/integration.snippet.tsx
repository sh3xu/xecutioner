/**
 * NOTE: Illustrative React Native integration (~10 lines).
 * Not compiled as part of the Node demo; copy into an Expo/RN app.
 */

import { createUiClient } from "@xecutioner/react-native";
import { useEffect, useRef } from "react";
import { View } from "react-native";

export function AiUiBridge(props: { sessionId: string; url: string }) {
  const rootRef = useRef<View>(null);

  useEffect(() => {
    const client = createUiClient({
      url: props.url,
      sessionId: props.sessionId,
      hooks: {
        getRootNode: () => ({
          testID: "app-root",
          // NOTE: Replace with accessibility-tree walk in production hosts.
          children: [],
        }),
      },
    });
    void client.connect();
    return () => client.disconnect();
  }, [props.sessionId, props.url]);

  return <View ref={rootRef} collapsable={false} />;
}
