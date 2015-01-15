#ifndef __drcgrid_bot_renderer_h__
#define __drcgrid_bot_renderer_h__

/**
 * Linking: `pkg-config --libs drcgrid-renderer`
 * @{
 */

#include <lcm/lcm.h>

#include <bot_vis/bot_vis.h>
#include <bot_frames/bot_frames.h>

#ifdef __cplusplus
extern "C" {
#endif

void drcgrid_add_renderer_to_viewer(BotViewer* viewer, int priority,lcm_t* lcm);

/**
 * @}
 */

#ifdef __cplusplus
}
#endif

#endif