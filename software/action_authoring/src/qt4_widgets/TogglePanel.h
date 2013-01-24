#ifndef TOGGLEPANEL_H
#define TOGGLEPANEL_H

#include <QtGui>
#include <boost/shared_ptr.hpp>
#include "ExtendedLabel.h"

class TogglePanel : public QWidget
{
    Q_OBJECT

private:
    QWidget* _headerArea;
    QString _headerText;
    QWidget* _widgetArea;
    QPushButton* icon;
    ExtendedQLabel* _headerTextLabel;
    QVBoxLayout* _widgetLayout;
    int _state;
    QObject* _parent;

public:
    ~TogglePanel();
    TogglePanel(QObject *parent, QString headerText);
    void addWidget(QWidget *widget);
    void addLayout(QLayout *layout);
    void setSelected(bool selected);
    void setTitle(QString title);
    QSize sizeHint() const { return QSize(_widgetArea->sizeHint().width(), _widgetArea->sizeHint().height() + _headerArea->sizeHint().height()); }

    enum { OPEN, CLOSED };

private slots:
    void changeState();
};

#endif // TOGGLEPANEL_H
