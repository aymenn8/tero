import SwiftUI

struct SelectionUtilityView: View {
  @Bindable var session: SelectionUtilitySession
  let close: () -> Void
  var body: some View {
    if let message=session.message {
      VStack(alignment:.leading,spacing:10){
        HStack{TeroModeTitle(title:session.action.title);Spacer();Button(action:close){Image(systemName:"xmark")}.buttonStyle(TeroQuietButtonStyle()).accessibilityLabel("Close")}
          .overlay(alignment:.bottom) {TeroHeaderDivider().padding(.horizontal,-14).offset(y:5)}
        Text(message).font(.system(size:12)).foregroundStyle(.secondary)
        Button("Back",action:close).buttonStyle(TeroQuietButtonStyle())
      }.padding(14).frame(width:340).background{TeroReadingSurface()}
    }else{
      VStack(alignment:.leading,spacing:6){
        if !session.busy {ModeHint(text: session.label)}
        let choices=session.presentation
        ModeChoiceRow(step:choices.step,activityTitle:choices.activityTitle,finished:false,
                      searchQuery:choices.searchQuery,search:choices.search,choose:choices.activate){
          if session.choosingDate {
            DatePicker("Source date",selection:$session.date,displayedComponents:.date).labelsHidden().datePickerStyle(.field).environment(\.timeZone, session.sourceTimeZone).frame(width:120,height:30)
          }
        }
      }
    }
  }
}
