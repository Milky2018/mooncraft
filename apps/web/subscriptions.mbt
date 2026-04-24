///|
fn subscriptions(dispatch : @rabbita.Dispatch[Msg], model : Model) -> @sub.Sub {
  if model.boot_requested {
    return @sub.none
  }
  @sub.custom_sub(
    "bootstrap",
    @sub.Local,
    ScheduleBootstrap(dispatch(Bootstrap)),
    @sub.SubLoader((payload, scheduler) => {
      match payload {
        ScheduleBootstrap(cmd) => {
          scheduler.add(cmd)
          None
        }
        _ => None
      }
    }),
  )
}
